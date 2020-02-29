# OWT-DOCKER

Docker for [owt-server](https://github.com/open-webrtc-toolkit/owt-server).

## Usage

目前提供OWT 4.3的镜像开发环境，若需要更新代码需要修改Dockerfile，或者参考[Deubg](#debug)重新编译。启动OWT环境：

```bash
docker run -it -p 3004:3004 -p 8080:8080 -p 60000-60050:60000-60050/udp \
    registry.cn-hangzhou.aliyuncs.com/ossrs/owt:4.3 bash
```

> Note: Docker使用的版本是[owt-server 4.3](https://github.com/open-webrtc-toolkit/owt-server/releases/tag/v4.3), [owt-client 4.3](https://github.com/open-webrtc-toolkit/owt-client-javascript/releases/tag/v4.3), [IntelMediaSDK 18.4.0](https://github.com/Intel-Media-SDK/MediaSDK/releases/download/intel-mediasdk-18.4.0/MediaStack.tar.gz).

> Note: OWT需要开一系列范围的UDP端口，docker映射大范围端口会有问题，所以我们只指定了50个测试端口，启动owt-server后需要修改配置文件。

然后输入启动命令：

```
./dist/bin/init-all.sh && ./dist/bin/start-all.sh
```

## Update

如果需要修改代码后编译，可以将本地的代码映射到docker。

首先，假设你的代码是在`~/git/owt-server`这个目录：

```bash
mkdir -p ~/git && cd ~/git &&
git clone https://github.com/open-webrtc-toolkit/owt-server.git
```

其次，可以启动时开启`--privileged`允许gdb调试，将本地的source目录映射到docker：

``` bash
cd ~/git/owt-server &&
docker run -it -p 3004:3004 -p 8080:8080 -p 60000-60050:60000-60050/udp \
    --privileged -v `pwd`/source:/tmp/git/owt-docker/owt-server-4.3/source
    registry.cn-hangzhou.aliyuncs.com/ossrs/owt:4.3 bash
```

> Remark: 只映射代码source目录，不要覆盖了依赖例如build等目录。

最后，修改本地的代码后，在远程编译和运行owt：

```bash
TBD
```

## Dependencies

OWT会安装很多依赖的库，详细可以参考Dockerfile中安装的依赖。

这些代码和依赖都会在docker中，下载代码包括：

* node_modules/nan
* build, 734M
    * build/libdeps/ffmpeg-4.1.3.tar.bz2
    * build/libdeps/libnice-0.1.4.tar.gz
    * build/libdeps/openssl-1.0.2t.tar.gz
    * build/libdeps/libsrtp-2.1.0.tar.gz
* third_party, 561M
    * third_party/quic-lib, 8.4M
    * third_party/licode, 34M
    * third_party/openh264, 33M
    * third_party/SVT-HEVC, 39M
    * third_party/webrtc, 448M

## Issues

1. OWT UDP端口没有复用，导致需要开一系列端口。

## Tips

如果发现自己的Docker太大，可以先把一些镜像导出，比如：

```bash
docker save registry.cn-hangzhou.aliyuncs.com/ossrs/owt:pack -o owt-pack.tar
```

删除Docker文件，可以选择下面任意方式删除Docker的磁盘文件：

* 点`Reset`，然后点`Remove all data`。
* 点`Disk`，然后点`Open in Finder`，直接删除`Docker.qcow2`，然后重启Docker。

Docker重启后，导入你要的镜像，例如：

```bash
docker load -i owt-pack.tar
```

这样就可以将Docker占用的临时磁盘空间彻底瘦身。


