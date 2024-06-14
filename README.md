# 视频拼接服务

音视频编辑服务MediaEditorServer，缩写为：UMES，提供音视频的编辑能力

默认端口：7070，提供HTTP服务，HTTP-JSON 的Restful风格的无状态服务

支持默认转场效果：20个

视频拼接服务要求拼接的视频文件编码格式yuv，分辨率，帧率要完全一致，且仅支持H264的视频编码

默认的最大并行任务数5个


# 功能列表
- 音视频的多视频拼接
- 视频转场
- 充分利用硬件的加速效果，提供更加高效的音视频的处理能力
- 服务版本信息查询
- 任务状态查询
- 任务完成异步通知
- 日志管理，最多保存30天的日志
- 辅助测试工具

## 接口列表
可以查看源码，postman，doc/接口介绍
```bash
1.视频拼接 POST/index/api/videoCombiner
2.版本信息 GET/index/api/version
3.通知接口调用端维护 POST/index/api/OnNotify
4.查询服务状态 GET/index/api/serverStatus
5.查询服务全局配置项 GET/index/api/config
6.设置服务全局配置项 PUT/index/api/config
7.查询任务状态 GET/index/api/taskStatus/{taskID}

```
# 视频格式
支持H264 MP4码流的视频拼接，例如:['1.mp4','2.mp4','3.mp4']

# 硬件加速
使用专属的硬件Nvidia Cuda 可以开启常驻显存模式nvidia-smi -pm 1 来实现硬件加速的效果，利用nvEnc、nvDec的硬件编解码单元来提速，使用cuda_12.5.0_555.42.02_linux.run统一安装，可以解决调用过程中的掉卡，显存不足的问题
- 通过nvidia-smi dmon 查看使用的效果
- NVIDIA-SMI 555.42.02             
- Driver Version: 555.42.02   
- CUDA Version: V12.5.40

# 转场
支持多个短视频拼接，同时支持配置多个转场设置，多个短视频依次选择多个多个转场效果，若配置1个转场效果则，短视频拼接即使用一个转场，
例如：短视频文件['1.mp4','2.mp4','3.mp4','4.mp4'] 转场设置['circlecrop','circleopen'] 则1.mp4+circlecrop+2.mp4+circleopen+3.mp4+circlecrop+4.mp4
- circlecrop: 圆形裁剪效果
- circleopen: 圆形打开效果
- circleclose: 圆形关闭效果
- dissolve: 溶解效果
- fadeblack: 黑色淡入淡出效果
- fadewhite: 白色淡入淡出效果
- fade: 淡入淡出效果
- horzopen: 水平打开效果
- horzclose: 水平关闭效果
- pixelize: 像素化效果
- radial: 放射状效果
- rectcrop: 矩形裁剪效果
- slideleft: 从右向左滑动效果
- slideright: 从左向右滑动效果
- slideup: 从下向上滑动效果
- slidedown: 从上向下滑动效果
- wipeleft: 从右向左擦除效果
- wiperight: 从左向右擦除效果
- wipeup: 从下向上擦除效果
- wipedown: 从上向下擦除效果

# docker构建
由于使用的是Ubuntu 24.04 所以需要主机系统18.04(含)之后，docker版本需要大于Docker version 20.10.10，
构建命令可参照：
```bash
sudo bash ./generate_version.sh
tag_time=$(date "+.%Y%m%d")
image_tag2=${image_tag}${tag_time}
platform=x86_64
image_name2=${image_name}"-"${platform}
sudo docker build --force-rm --no-cache -f=./Dockerfile -t ${image_name2}:${image_tag2} .
```
# 服务运行
如下命令运行：
```bash
docker run -itd --ulimit core=0 --gpus all -e NVIDIA_DRIVER_CAPABILITIES=all --name umes --hostname umes --privileged=true --net=host -v /data/:/data -v /usr/local/cuda/:/usr/local/cuda/ reg.uni-ubi.com/audiovideoservice/umes-x86:1.0.1.20240522
```

服务运行的工作目录/opt/umes/ 默认端口：7070

可以参照doc/视频拼接服务接口文档.docx简单的接口介绍和源代码通过postman即可进行接口测试

# 系统内核调优

## 结合系统本身硬件情况调优，根据如下系统和业务场景的调优参数如下：
```bash
root@alg-dev17:~# free -h
               total        used        free      shared  buff/cache   available
Mem:            15Gi       3.5Gi       4.6Gi        62Mi       7.5Gi       6.3Gi
Swap:          3.8Gi       2.0Mi       3.8Gi
cat >> /etc/sysctl.conf <<- EOF
vm.min_free_kbytes = 450000
vm.watermark_scale_factor=500 
vm.swappiness = 60
vm.dirty_background_ratio = 10
vm.dirty_ratio = 20
vm.dirty_expire_centisecs = 50
vm.dirty_writeback_centisecs = 50
vm.vfs_cache_pressure = 1000
vm.extfrag_threshold = 200
vm.dirtytime_expire_seconds = 300
kernel.numa_balancing=0
net.ipv4.tcp_syncookies = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_max_tw_buckets = 20000
net.ipv4.tcp_keepalive_time = 120
net.ipv4.tcp_keepalive_intvl = 5
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_mem = 94500000 915000000 927000000
net.core.somaxconn = 65535
net.ipv4.ip_local_port_range = 1024 65536
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_window_scaling = 0
net.ipv4.tcp_sack = 0
net.core.netdev_max_backlog = 30000
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_max_orphans = 262144
fs.file-max = 6553600
kernel.watchdog_thresh=30
EOF

sysctl -p
```

## 在高压力的情况下还是需要定期整理内存，否则会显存报错，根据业务压力调整时间周期
```bash
sync&&echo 1 > /proc/sys/vm/drop_caches
```

# 授权协议
本项目自有代码使用宽松的MIT协议，在保留版权信息的情况下可以自由应用于各自商用、非商业的项目。 但是本项目也零碎的使用了一些其他的开源代码，在商用的情况下请自行替代或剔除； 由于使用本项目而产生的商业纠纷或侵权行为一概与本项目及开发者无关，请自行承担法律风险。 在使用本项目代码时，也应该在授权协议中同时表明本项目依赖的第三方库的协议。

# 鸣谢
脚本实现参照了https://github.com/qq2225936589/xfade-ffmpeg-script