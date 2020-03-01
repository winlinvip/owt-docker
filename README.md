# OWT-DOCKER

Docker for [owt-server](https://github.com/open-webrtc-toolkit/owt-server).

## Usage

下面我们以MacPro为例，如何使用镜像搭建内网Demo，其他OS将命令替换就可以。

**Step 0:** 当然你得有个Docker。

可以从[docker.io](https://www.docker.com/products/docker-desktop)下载一个，安装就好了。
执行`docker version`，应该可以看到Docker版本：

```bash
Mac:owt-docker chengli.ycl$ docker version
Client:
 Version:	17.12.0-ce
Server:
  Version:	17.12.0-ce
```

**Step 1:** 通过Docker镜像，启动OWT环境。

```bash
docker run -it -p 3004:3004 -p 8080:8080 -p 60000-60050:60000-60050/udp \
    registry.cn-hangzhou.aliyuncs.com/ossrs/owt:config bash
```

> Note: Docker使用的版本是[owt-server 4.3](https://github.com/open-webrtc-toolkit/owt-server/releases/tag/v4.3), [owt-client 4.3](https://github.com/open-webrtc-toolkit/owt-client-javascript/releases/tag/v4.3), [IntelMediaSDK 18.4.0](https://github.com/Intel-Media-SDK/MediaSDK/releases/download/intel-mediasdk-18.4.0/MediaStack.tar.gz).

> Note: OWT需要开一系列范围的UDP端口，docker映射大范围端口会有问题，所以我们只指定了50个测试端口，已经在镜像中修改了配置，参考[Port Range](#port-range)。

**Step 2:** 设置OWT的IP信息，设置为Mac的IP地址。也可以自动获取和设置IP，参考[Usage: HostIP](#usage-hostip)。

```bash
# vi dist/webrtc_agent/agent.toml
[webrtc]
network_interfaces = [{name="eth0",replaced_ip_address="192.168.1.4"}]  # default: []

# vi dist/portal/portal.toml
[portal]
ip_address = "192.168.1.4" #default: ""
```

**Step 3:** 输入命令，初始化OWT和启动服务。

```bash
cd dist && ./bin/init-all.sh && ./bin/start-all.sh
```

> Remark: 注意会有个提示是否添加MongoDB账号，`Update RabbitMQ/MongoDB Account?`，可以忽略或写No（默认5秒左右就会忽略）。

**Step 4:** 大功告成。

打开OWT的默认演示页面，私有证书需要选择`Advanced => Proceed to xxx`：

* https://192.168.1.4:3004/

> Remark: 由于证书问题，第一次需要在浏览器，先打开OWT信令服务(Portal)页面（后续就不用了）：

* https://192.168.1.4:8080/

> Note: 我们也可以使用域名来访问OWT服务，这样就不用每次IP变更后修改配置文件，参考[Usage: HostIP](#usage-hostip)。

> Note: 目前提供OWT 4.3的镜像开发环境，若需要更新代码需要修改Dockerfile，或者参考[Deubg](#debug)重新编译。

还可以尝试其他方式，比如：

* 在内网使用镜像快速搭建OWT，需要修改IP，参考[Usage](#usage)。
* 在内网用镜像搭建OWT，使用脚本自动获取IP，自动修改OWT配置文件中的IP，参考[Usage: HostIP](#usage-hostip)。
* 有公网IP或域名时，用镜像搭建OWT服务，参考[Usage: Internet](#usage-internet)。

## Usage: HostIP

在之前[Usage](#usage)中，我们说明了如何在内网用镜像快速搭建OWT服务，但需要修改OWT的配置文件。
这里我们说明如何使用脚本自动获取IP，自动修改OWT配置文件中的IP。

下面我们以MacPro为例，如何使用镜像搭建内网Demo，其他OS将命令替换就可以。

**Step 0:** 当然你得有个Docker。

可以从[docker.io](https://www.docker.com/products/docker-desktop)下载一个，安装就好了。
执行`docker version`，应该可以看到Docker版本：

```bash
Mac:owt-docker chengli.ycl$ docker version
Client:
 Version:	17.12.0-ce
Server:
  Version:	17.12.0-ce
```

**Step 1:** 先获取宿主机的IP，该IP需要在访问的机器上能Ping通。

```bash
HostIP=`ifconfig en0 inet| grep inet|awk '{print $2}'`
```

上面是Mac的脚本，Linux上需要更换，也可以下载脚本获取：

```bash
HostIP=`curl -sSL https://raw.githubusercontent.com/ossrs/srs-docker/v3/auto/get_host_ip.sh | bash`
```

或者直接设置为自己的IP：

```bash
HostIP="192.168.1.4"
```

**Step 2:** 设置访问机器的hosts。

> Remark: 注意是访问机器的hosts，也就是浏览器所在的机器的hosts。

由于宿主机的IP可能会变，所以我们使用域名`docker-host`来访问OWT，需要在访问机器(**浏览器所在机器**)的`/etc/hosts`中加一条记录，脚本如下：

```bash
HostIP=`ifconfig en0 inet| grep inet|awk '{print $2}'` && sudo chown `whoami` /etc/hosts &&
if [[ `grep -q docker-host /etc/hosts && echo 'YES'` == 'YES' ]]; then
    sed "s/^.*docker-host/$HostIP docker-host/g" /etc/hosts >/tmp/hosts && cat /tmp/hosts > /etc/hosts && rm -f /tmp/hosts;
else
    echo "" >> /etc/hosts && echo "# For OWT docker" >> /etc/hosts && echo "$HostIP docker-host" >> /etc/hosts;
fi &&
sudo chown root /etc/hosts && echo "Hosts patching done:" && grep docker-host /etc/hosts
```

> Remark: 也可以直接在`/etc/hosts`中加一条，比如`192.168.1.4 docker-host`。

> Remark: 注意脚本中使用了`sudo`修改hosts，所以可能会要求输入密码。

**Step 3:** 通过Docker镜像，启动OWT环境。

```bash
HostIP=`ifconfig en0 inet| grep inet|awk '{print $2}'` &&
docker run -it -p 3004:3004 -p 8080:8080 -p 60000-60050:60000-60050/udp \
    --add-host=docker-host:$HostIP \
    registry.cn-hangzhou.aliyuncs.com/ossrs/owt:4.3 bash
```

> Note: Docker使用的版本是[owt-server 4.3](https://github.com/open-webrtc-toolkit/owt-server/releases/tag/v4.3), [owt-client 4.3](https://github.com/open-webrtc-toolkit/owt-client-javascript/releases/tag/v4.3), [IntelMediaSDK 18.4.0](https://github.com/Intel-Media-SDK/MediaSDK/releases/download/intel-mediasdk-18.4.0/MediaStack.tar.gz).

> Note: OWT需要开一系列范围的UDP端口，docker映射大范围端口会有问题，所以我们只指定了50个测试端口，已经在镜像中修改了配置，参考[Port Range](#port-range)。

> Note: OWT对外提供了信令和媒体服务，所以需要返回可外部访问的IP地址，而Docker相当于内网，所以启动时需要指定`docker-host`这个地址，当然也可以直接修改配置，参考[Docker Host IP](#docker-host-ip)。

**Step 4:** 输入命令，初始化OWT和启动服务。

```bash
cd dist && ./bin/init-all.sh && ./bin/start-all.sh
```

> Remark: 注意会有个提示是否添加MongoDB账号，`Update RabbitMQ/MongoDB Account?`，可以忽略或写No（默认5秒左右就会忽略）。

**Step 5:** 大功告成。

打开OWT的默认演示页面，私有证书需要选择`Advanced => Proceed to xxx`：

* https://docker-host:3004/

> Remark: 由于证书问题，第一次需要在浏览器，先打开OWT信令服务(Portal)页面（后续就不用了）：

* https://docker-host:8080/

> Note: 我们使用域名来访问OWT服务，这样宿主机IP变更后，只需要执行脚本就可以，参考[Docker Host IP](#docker-host-ip)。

> Note: 目前提供OWT 4.3的镜像开发环境，若需要更新代码需要修改Dockerfile，或者参考[Deubg](#debug)重新编译。

还可以尝试其他方式，比如：

* 在内网使用镜像快速搭建OWT，需要修改IP，参考[Usage](#usage)。
* 在内网用镜像搭建OWT，使用脚本自动获取IP，自动修改OWT配置文件中的IP，参考[Usage: HostIP](#usage-hostip)。
* 有公网IP或域名时，用镜像搭建OWT服务，参考[Usage: Internet](#usage-internet)。

## Usage: Internet

> Remark: 下面说明公网IP或域名搭建OWT环境，若在内网或本机使用Docker快速搭建OWT开发环境，参考[Usage:](#usage)。

**Step 1:** 通过Docker镜像，启动OWT环境。

```bash
docker run -it -p 3004:3004 -p 8080:8080 -p 60000-60050:60000-60050/udp \
    registry.cn-hangzhou.aliyuncs.com/ossrs/owt:config bash
```

> Note: Docker使用的版本是[owt-server 4.3](https://github.com/open-webrtc-toolkit/owt-server/releases/tag/v4.3), [owt-client 4.3](https://github.com/open-webrtc-toolkit/owt-client-javascript/releases/tag/v4.3), [IntelMediaSDK 18.4.0](https://github.com/Intel-Media-SDK/MediaSDK/releases/download/intel-mediasdk-18.4.0/MediaStack.tar.gz).

> Note: OWT需要开一系列范围的UDP端口，docker映射大范围端口会有问题，所以我们只指定了50个测试端口，已经在镜像中修改了配置，参考[Port Range](#port-range)。

**Step 2:** 配置公网IP或域名，参考[Use Internet Name](#use-internet-name)。

```bash
# vi dist/webrtc_agent/agent.toml
[webrtc]
network_interfaces = [{name="eth0",replaced_ip_address="182.28.12.12"}]  # default: []

# vi dist/portal/portal.toml
[portal]
ip_address = "182.28.12.12" #default: ""
```

**Step 3:** 输入命令，初始化OWT和启动服务。

```bash
cd dist && ./bin/init-all.sh && ./bin/start-all.sh
```

> Remark: 注意会有个提示是否添加MongoDB账号，可以忽略或写No（默认5秒左右就会忽略）。

**Step 4:** 大功告成。由于证书问题，需要打开页面：

* https://182.28.12.12:8080/ 第一次先访问下信令，若使用域名则不需要手动访问。
* https://182.28.12.12:3004/ OWT演示页面。

> Note: 目前提供OWT 4.3的镜像开发环境，若需要更新代码需要修改Dockerfile，或者参考[Deubg](#debug)重新编译。

还可以尝试其他方式，比如：

* 在内网使用镜像快速搭建OWT，需要修改IP，参考[Usage](#usage)。
* 在内网用镜像搭建OWT，使用脚本自动获取IP，自动修改OWT配置文件中的IP，参考[Usage: HostIP](#usage-hostip)。
* 有公网IP或域名时，用镜像搭建OWT服务，参考[Usage: Internet](#usage-internet)。

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
HostIP=`ifconfig en0 inet| grep inet|awk '{print $2}'` &&
docker run -it -p 3004:3004 -p 8080:8080 -p 60000-60050:60000-60050/udp \
    --privileged -v `pwd`/source:/tmp/git/owt-docker/owt-server-4.3/source
    --add-host=docker-host:$HostIP \
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

1. OWT UDP端口没有复用，导致需要开一系列端口，参考[Port Range](#port-range)。

## Port Range

Docker由于需要映射端口，所以如果需要开特别多的UDP端口会有问题，Mac下的Docker能开50个左右的UDP端口，测试是够用了。

我们在镜像中已经修改了配置文件，将端口范围改成了`60000-60050/udp`，如果有需要可以自己改：

```bash
# vi dist/webrtc_agent/agent.toml
[webrtc]
maxport = 60050 #default: 0
minport = 60000 #default: 0
```

> Note: 注意别改错了，还有另外个地方也有这个配置，`[internal]`这个是配置集群的，单个Docker不用修改。

## Docker Host IP

OWT在Docker中运行时，Docker就相当于一个局域网，OWT获取到地址是个内网IP，在外面是无法访问的，所以需要修改配置。

比如，我们在Docker中查看OWT的IP，可以发现是`eth0 172.17.0.2`：

```bash
root@d3041e7dd80d:/tmp/git/owt-docker/owt-server-4.3# ifconfig eth0| grep inet
        inet 172.17.0.2  netmask 255.255.0.0  broadcast 172.17.255.255
```

我们在Host机器（也就是运行Docker的机器上）查看IP，可以发现是`en0 192.168.1.4`(以Mac为例)：

```bash
Mac:owt-docker chengli.ycl$ ifconfig en0 inet|grep inet
	inet 192.168.1.4 netmask 0xffffff00 broadcast 192.168.1.255
```

那么我们就需要修改OWT的配置，让它知道自己应该对外使用`192.168.1.4`这个宿主机的地址（当然如果有公网IP也可以）。

* `dist/webrtc_agent/agent.toml`，修改`[webrtc]`中的`network_interfaces`，是媒体流的服务地址。
* `dist/portal/portal.toml`，修改`[portal]`中的`ip_address`，是信令的服务地址。

Docker提供了更好的办法，可以将宿主机的IP(192.168.1.4)通过`--add-host`传给OWT，映射成一个域名`docker-host`：

```bash
HostIP=`ifconfig en0 inet| grep inet|awk '{print $2}'` &&
docker run -it --add-host=docker-host:$HostIP \
    registry.cn-hangzhou.aliyuncs.com/ossrs/owt:4.3 bash
```

> Remark: 注意应该映射端口，这里为了强调域名就没有把端口映射写上。

这样在Docker中就可以知道宿主机的IP地址了（或者公网IP也可以）：

```bash
root@d5a5bc41169e:/tmp/git/owt-docker/owt-server-4.3# ping docker-host
PING docker-host (192.168.1.4): 56 data bytes
64 bytes from 192.168.1.4: icmp_seq=0 ttl=37 time=1.002 ms
64 bytes from 192.168.1.4: icmp_seq=1 ttl=37 time=5.884 ms
```

我们就可以将OWT对外暴露的服务，修改为域名`docker-host`，避免每次启动都要改配置：

```bash
# vi dist/webrtc_agent/agent.toml
[webrtc]
network_interfaces = [{name="eth0",replaced_ip_address="docker-host"}]  # default: []

# vi dist/portal/portal.toml
[portal]
ip_address = "docker-host" #default: ""
```

由于这个地址会被返回给浏览器，所以需要我们修改客户端所在机器的host文件：

```bash
HostIP=`ifconfig en0 inet| grep inet|awk '{print $2}'` &&
sudo chown `whoami` /etc/hosts &&
if [[ `grep -q docker-host /etc/hosts && echo 'YES'` == 'YES' ]]; then
    sed "s/^.*docker-host/$HostIP docker-host/g" /etc/hosts >/tmp/hosts &&
    cat /tmp/hosts > /etc/hosts && rm -f /tmp/hosts;
else
    echo "" >> /etc/hosts &&
    echo "# For OWT docker" >> /etc/hosts &&
    echo "$HostIP docker-host" >> /etc/hosts;
fi &&
sudo chown root /etc/hosts &&
echo "Host Patching Done:" && grep docker-host /etc/hosts
```

<a name="use-internet-name"></a>

当然，若有公网可以访问的域名，或者公网IP，直接修改为IP或域名也可以：

```bash
# vi dist/webrtc_agent/agent.toml
[webrtc]
network_interfaces = [{name="eth0",replaced_ip_address="192.168.1.4"}]  # default: []

# vi dist/portal/portal.toml
[portal]
ip_address = "192.168.1.4" #default: ""
```


