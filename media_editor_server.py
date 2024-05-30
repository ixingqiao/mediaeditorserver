import os
import json
import subprocess
import logging
import threading
import hashlib
import time
import requests
import psutil
from flask import Flask, request, jsonify
from logging.handlers import TimedRotatingFileHandler

# 创建日志目录
if not os.path.exists('./logs'):
    os.makedirs('./logs')

# 设置日志记录器
log_formatter = logging.Formatter('[%(asctime)s-%(thread)d-%(levelname)s-%(funcName)s-%(lineno)d] %(message)s')

# 设置日志处理程序，每天24点分割，最多保存30天日志
log_handler = TimedRotatingFileHandler('./logs/umes_server.log', when='midnight', interval=1, backupCount=30)
log_handler.setLevel(logging.INFO)
log_handler.setFormatter(log_formatter)
log_handler.suffix = "%Y%m%d.log"

# 将处理程序添加到日志记录器
logger = logging.getLogger('umes_server')
logger.addHandler(log_handler)
logger.setLevel(logging.INFO)

app = Flask(__name__)

# 默认输出路径
XFADE_OUTPUT_PATH = '/data/xfade'
# 默认通知地址
DEFAULT_NOTIFICATION_URL = 'http://127.0.0.1:7070/index/api/OnNotify'

# 最大并行任务数
MAX_CONCURRENT_TASKS = 5
# 并行任务计数器
current_tasks = 0
# 任务ID计数器
task_counter = 0

# 锁，用于并发控制
lock = threading.Lock()

def generate_unique_filename():
    """生成包含时间戳和哈希的唯一文件名"""
    timestamp = time.strftime('%Y%m%d%H%M%S')
    hash_object = hashlib.sha256(os.urandom(32))
    hash_str = hash_object.hexdigest()[:8]
    return f"{XFADE_OUTPUT_PATH}/merge-{timestamp}-{hash_str}.mp4"

def terminate_process_and_children(proc):
    """终止进程及其子进程"""
    try:
        logger.error(f'terminating process: {proc.pid}')
        parent = psutil.Process(proc.pid)
        children = parent.children(recursive=True)
        for child in children:
            logger.error(f'terminating child process: {child.pid}')
            child.kill()
        psutil.wait_procs(children, timeout=5)  # 等待子进程终止
        parent.terminate()  # 终止父进程
        parent.wait(5)  # 等待父进程终止
    except Exception as e:
        logger.error(f'Error terminating process: {e}')

def send_task_status_notification(notification_url, task_id, status, message, output_path):
    """发送任务状态通知"""
    if notification_url:
        for attempt in range(5):
            try:
                response = requests.post(notification_url, json={
                    'taskId': task_id,
                    'status': status,
                    'message': message,
                    'outputFile': output_path
                }, timeout=5)  # 设置超时时间为5秒
                if response.status_code == 200:
                    logger.info(f'Notification sent for task {task_id} status_code: {response.status_code}')
                    break  # 发送成功，退出循环
                else:
                    logger.error(f'Unexpected response code {response.status_code} for task {task_id} on attempt {attempt + 1}')
            except requests.RequestException as e:
                logger.error(f'Failed to send notification for task {task_id} on attempt {attempt + 1}: {e}')
            except Exception as e:
                logger.error(f'exceptiton to send notification for task {task_id} on attempt {attempt + 1}: {e}')
            time.sleep(attempt * 5)  # 重试5次

def execute_task(notification_url, task_id, video_files, transitions, output_path, interval):
    logger.info(f'execute_task begin {task_id} {output_path}')
    global current_tasks
    try:
        # 生成命令
        cmd = ['/opt/umes/xfade-transitions.sh']
        if video_files:
            cmd.extend(['--files'] + video_files)
        if transitions:
            cmd.extend(['--transitions'] + transitions)
        if output_path:
            cmd.extend(['--output', output_path])
        if interval:
            cmd.extend(['--interval', str(interval)])

        # 运行命令
        status = 'failed'
        error_message = ''
        logger.info(f'task_id {task_id} Popen cmd: {cmd}')
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

        #实时刷新任务日志
        def log_output(proc, task_id):
            logger.info("log thread begin for process: {proc.pid}")
            for line in iter(proc.stdout.readline, ''):
                if line:
                    logger.info(f'task_id:{task_id} {line.strip()}')
            logger.info("log_output thread end")

        log_thread = threading.Thread(target=log_output, args=(proc, task_id),name="log_output")
        log_thread.start()
        
        try:
            # 任务的最大运行时间
            proc.wait(timeout=300)
            # terminate_process_and_children(proc)
            # logger.info(f'{stdout}')
            if proc.returncode != 0:
                error_message = f'Task failed: {proc.returncode}'
                logger.error(error_message)
            else:
                status = 'success'
                logger.info(f'Task completed successfully: {output_path}')
        except subprocess.TimeoutExpired:
            error_message = f'Task timeout expired: {output_path}'
            logger.error(error_message)
            terminate_process_and_children(proc)
    except Exception as e:
        error_message = f'Error executing task: {e}'
        logger.error(error_message)
    finally:
        log_thread.join(timeout=5)  # 等待线程结束
        if log_thread.is_alive():
            logger.error("log thread, killing")
            log_thread.kill()
        # 释放并行任务计数器
        with lock:
            current_tasks -= 1
            logger.info(f'number of tasks: {current_tasks}')
        # 发送任务执行结果通知
        send_task_status_notification(notification_url, task_id, status, error_message, output_path)
        logger.info(f'execute_task end')

@app.route('/index/api/videoCombiner', methods=['POST'])
def merge_video():
    global current_tasks, task_counter
    try:
        post_params = request.get_json()
        if not post_params:
            logger.error('No JSON payload provided')
            return jsonify({'code': 1003, 'msg': 'Invalid input: No JSON payload provided'}), 400
        video_files = post_params.get('videoFiles', [])
        transitions = post_params.get('transitions', [])
        output_path = post_params.get('outputFile', generate_unique_filename())
        interval = post_params.get('interval', 2)
        notification_url = post_params.get('notificationUrl', DEFAULT_NOTIFICATION_URL)

        if not isinstance(video_files, list) or not all(isinstance(item, str) for item in video_files):
            logger.error('Invalid videoFiles parameter')
            return jsonify({'code': 1004, 'msg': 'Invalid input: videoFiles must be a list of strings'}), 400
        if not video_files or not 2 <= len(video_files) <= 20:
            return jsonify({'code': 1004, 'msg': 'Invalid input: videoFiles '}), 400
        # 在执行任务之前检查视频文件是否存在
        for video_file in video_files:
            if not os.path.isfile(video_file):
                logger.error(f'Video file not found: {video_file}')
                return jsonify({'code': 1004, 'msg': f'Video file not found: {video_file}'}), 400
        
        if not isinstance(transitions, list) or not all(isinstance(item, str) for item in transitions):
            logger.error('Invalid transitions parameter')
            return jsonify({'code': 1005, 'msg': 'Invalid input: transitions must be a list of strings'}), 400

        if not isinstance(interval, int) or interval <= 0:
            logger.error('Invalid interval parameter')
            return jsonify({'code': 1006, 'msg': 'Invalid input: interval must be a positive integer'}), 400

        if notification_url and not isinstance(notification_url, str):
            logger.error('Invalid notificationUrl parameter')
            return jsonify({'code': 1009, 'msg': 'Invalid input: notificationUrl must be a string'}), 400

        # 检查当前任务数是否已经达到最大值
        with lock:
            if current_tasks >= MAX_CONCURRENT_TASKS:
                logger.error('Exceeded maximum concurrent tasks')
                return jsonify({'code': 1001, 'msg': 'Exceeded maximum concurrent tasks'}), 500
            current_tasks += 1
            task_counter += 1
            logger.info(f'number of tasks: {current_tasks}')
        try:
            # 执行视频拼接线程
            task_id = hashlib.md5((str(time.time()) + output_path).encode('utf-8')).hexdigest()[:8]
            logger.info(f'Task: {task_id} {video_files} {transitions} {output_path} {interval} {notification_url}')
            task_thread = threading.Thread(target=execute_task, args=(notification_url, task_id, video_files, transitions, output_path, interval), name="execute_task")
            task_thread.start()
        except Exception as e:
            with lock:
                current_tasks -= 1
                logger.error(f'Failed to start thread: {e}', exc_info=True)
            return jsonify({'code': 1008, 'msg': 'Failed to start processing thread'}), 500

        # 返回任务提交成功的响应
        return jsonify({'code': 0, 'msg': 'Task submitted successfully', 'data': {'taskId': task_id, 'outputFile': output_path}})
    except Exception as e:
        logger.error(f'Error processing request: {e}', exc_info=True)
        return jsonify({'code': 1002, 'msg': 'Internal Server Error'}), 500

@app.route('/index/api/tasksStatus', methods=['GET'])
def status():
    return jsonify({
        'code': 0, 
        'msg': '', 
        'data': {
            'currTasks': current_tasks, 
            'maxTasks': MAX_CONCURRENT_TASKS,
            'taskCounter':task_counter, 
            'defaultOutputPath':XFADE_OUTPUT_PATH, 
            'defaultNotifyUrl': DEFAULT_NOTIFICATION_URL
         }
    })

@app.route('/index/api/version', methods=['GET'])
def version():
    try:
        version_file_path = './version.json'
        if os.path.exists(version_file_path):
            with open(version_file_path, 'r') as version_file:
                version_info = json.load(version_file)
            return jsonify({'code': 0, 'msg': '', 'data': version_info})
        else:
            logger.error('version.json file not found')
            return jsonify({'code': 1007, 'msg': 'version.json file not found'}), 500
    except Exception as e:
        logger.error(f'Error reading version.json: {e}', exc_info=True)
        return jsonify({'code': 1002, 'msg': 'Internal Server Error'}), 500

# 自测异步通知地址
@app.route('/index/api/OnNotify', methods=['POST'])
def on_notify():
    try:
        post_params = request.get_json()
        logger.info(f'OnNotify post_params:{post_params}')
        return jsonify({'code': 0, 'msg': ''})

    except Exception as e:
        logger.error(f'Error: {e}', exc_info=True)
        return jsonify({'code': 1002, 'msg': 'Internal Server Error'}), 500

if __name__ == '__main__':
    logger.info("umes start ...")
    app.run(host='0.0.0.0', port=7070, threaded=True)
