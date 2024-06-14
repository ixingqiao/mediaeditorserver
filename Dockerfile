FROM ubuntu:24.04
ENV DEBIAN_FRONTEND noninteractive

# 阿里源
RUN  sed -i s@/archive.ubuntu.com/@/mirrors.aliyun.com/@g /etc/apt/sources.list

RUN apt-get clean 
RUN apt-get update && \
    apt-get install -y --no-install-recommends tzdata bc ffmpeg locales fonts-wqy-zenhei vim python3 python3-venv && \
    apt-get autoremove -y && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/umes /opt/umes/logs /opt/umes/example
ADD ./xfade-transitions.sh /opt/umes/xfade-transitions.sh
RUN chmod +x /opt/umes/xfade-transitions.sh

# 创建并激活虚拟环境，安装 Flask
RUN python3 -m venv /opt/umes/venv && \
    /opt/umes/venv/bin/pip install --upgrade pip && \
    /opt/umes/venv/bin/pip install flask requests psutil

# 设置中文编码
RUN locale-gen zh_CN.UTF-8
ENV LANG zh_CN.UTF-8  
ENV LANGUAGE zh_CN:zh  
ENV LC_ALL zh_CN.UTF-8 

# 设置时区
RUN ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && echo Asia/Shanghai > /etc/timezone

# 复制 Python 服务器脚本
ADD ./media_editor_server.py /opt/umes/media_editor_server.py
ADD ./version.json /opt/umes/version.json

WORKDIR /opt/umes/
ENV PATH /usr/local/cuda/bin:/opt/umes/:$PATH
ENV LD_LIBRARY_PATH /usr/local/cuda/lib64:$LD_LIBRARY_PATH

EXPOSE 7070/tcp

# 关闭core文件生成
RUN ulimit -c 0

# 设置容器启动命令
CMD ["/opt/umes/venv/bin/python", "/opt/umes/media_editor_server.py"]

# docker run -itd --ulimit core=0 --gpus all -e NVIDIA_DRIVER_CAPABILITIES=all --name umes --hostname umes --privileged=true --net=host -v /data/:/data -v /usr/local/cuda/:/usr/local/cuda/ reg.uni-ubi.com/audiovideoservice/umes-x86:1.0.1.20240522
