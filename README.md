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

# 视频格式
支持H264 MP4码流的视频拼接，例如:['1.mp4','2.mp4','3.mp4']

# 硬件加速
使用专属的硬件Nvidia Cuda 来实现硬件加速的效果，利用nvEnc、nvDec的硬件编解码单元来提速
- 通过nvidia-smi dmon 查看使用的效果
- NVIDIA-SMI 535.171.04             
- Driver Version: 535.171.04   
- CUDA Version: 12.2

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
sudo bash ./generate_version.sh
tag_time=$(date "+.%Y%m%d")
image_tag2=${image_tag}${tag_time}
platform=x86_64
image_name2=${image_name}"-"${platform}
sudo docker build --force-rm --no-cache -f=./Dockerfile -t ${image_name2}:${image_tag2} .

# 服务运行
如下命令运行：docker run -itd --gpus all -e NVIDIA_DRIVER_CAPABILITIES=all --name umes --hostname umes --privileged=true --net=host -v /data/:/data -v /usr/local/cuda/:/usr/local/cuda/ umes-x86:1.0.1.20240522

服务运行的工作目录/opt/umes/ 默认端口：7070

可以参照doc/视频拼接服务接口文档.docx简单的接口介绍和源代码通过postman即可进行接口测试