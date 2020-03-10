# Code Nodejs

OWT用nodejs调用了C++(例如WebRTC接收和解析流)，以`webrtc_agent`为例，分析这个过程。

* [Scripts](#scripts) 启动脚本分析。
* [Nodejs](#nodejs) 调试Nodejs脚本。
* [Schedule](#schedule) 调度，如何分配webrtc-agent。
* [WorkingNode](#workingnode) webrtc工作进程的启动和管理。
* [WebRTC](#webrtc) Nodejs如何调用WebRTC代码。
* [Videojs NAN](#nodejs-nan)Videojs如何调用C++代码。

## Scripts

启动服务的脚本是`./dist/bin/start-all.sh`，它的内容是：

```bash
${bin}/daemon.sh start webrtc-agent $1
```

这个脚本启动的是：

```bash
      webrtc-agent )
        cd ${OWT_HOME}/webrtc_agent
        export LD_LIBRARY_PATH=./lib:${LD_LIBRARY_PATH}
        nohup nice -n ${OWT_NICENESS} node . -U webrtc\
          > "${stdout}" 2>&1 </dev/null &
        echo $! > ${pid}
        ;;
```

翻译下变量，实际上执行的脚本是：

```bash
cd /tmp/git/owt-docker/owt-server-4.3/dist/webrtc_agent
export LD_LIBRARY_PATH=./lib:
nohup nice -n 0 node . -U webrtc > "/tmp/git/owt-docker/owt-server-4.3/dist/logs/webrtc-agent.stdout" 2>&1 </dev/null &
echo $! > /tmp/git/owt-docker/owt-server-4.3/dist/logs/webrtc-agent.pid
```

> Note: 是切换到了`dist/webrtc_agent`这个目录下面执行的。

> Note: 设置了`LD_LIBRARY_PATH`，是为了链接库`libnice.so.10`和`libusrsctp.so.1`。

> Note: 用`node . -U webrtc`启动了webrtc，启动node时用nice启动的，`nice -n 0`意思就是最高优先级，可以去掉这个没有关系。

> Note: 最后将node的pid（`$!`）写入了`dist/logs/webrtc-agent.pid`，停止服务时就可以找到进程了。

上面这些脚本的最终结果，我们可以停止webrtc_agent服务后，单独启动它：

```bash
(cd ./dist && ./bin/daemon.sh stop webrtc-agent) &&
(cd ./dist/webrtc_agent && node . -U webrtc)
```

可以看到，和直接脚本启动是一样的，不过没有PID管理和日志。

## Nodejs

上面分析到，启动`webrtc_agent`关键是用node启动了`./dist/webrtc_agent/index.js`：

```bash
(cd ./dist/webrtc_agent && node . -U webrtc)
```

我们可以用nodejs调试看下大致过程：

```bash
(cd ./dist/webrtc_agent && node inspect index.js -U webrtc)
```

1. `amqper.connect`和`amqper.asRpcClient`，连接到rabbitMQ消息队列，以RrcClient方式加入，可以设置断点`sb(193)`。
1. `joinCluster`和`clusterWorker`，加入集群，比如id=`webrtc-280b70d1ca0bc3333c3b@172.17.0.2`，purpose=`webrtc`，还带了调度信息比如负载和区域，设置了负载汇报函数`reportLoad`。
1. `amqper.asRpcServer`，作为RpcServer方式加入消息队列，这样可以收到调用消息，处理任务，可以被调用的函数定义在`rpcAPI`中。
1. `init_manager`，初始化进程管理，`fillNodes`启动预热子进程，`launchNode`是真正启动进程，这里有些配置值得注意。
    * `prerunNodeNum`，预热的(总是保持空闲的)进程数目，没有人进入房间，也会启动的进程，默认是2，配置文件`agent.toml`的`[agent]`中。
    * `maxNodeNum`，最大的Node进程数目，默认是13，配置文件`agent.toml`的`[agent]`中。
    * `reuseNode`，是否重用节点，这里是true，如果是audio、video、sip等就不重用，webrtc是重用的。
    * `consumeNodeByRoom`，是否按房间使用节点，如果是audio、video等就不按房间，webrtc是按房间使用节点。
1. `launchNode`，启动一个子进程进程，进程的参数如下。
    * `id`，值为`webrtc-51f1cfd00ed1e9d29a47@172.17.0.2_0`，如果查这个id可以看到启动了这个进程。
    * `spawnOptions.cmd`，值为`node`，也就是用node启动。
    * `spawnArgs`，值为[`'./workingNode'`, `'webrtc-51f1cfd00ed1e9d29a47@172.17.0.2_0'`, `'webrtc-51f1cfd00ed1e9d29a47@172.17.0.2'`, `'{"agent":{"maxProcesses":13,"prerunProcesses":2},"…_nicer":false,"io_workers":1},"purpose":"webrtc"}'`]，也就是启动的参数。

> Note: spec.reuseNode -Whether reuse the current in-use nodes if maxNodeNum has been reached.

> Note: spec.consumeNodeByRoom -Whether tasks from the same room be scheduled to the same node.

> Note: 对于`consumeNodeByRoom=true`，在大方会时比如一个房间有300人，就需要启动多个webrtc_agent，每个agent跑在一个节点，每个节点会启动多个进程(但只会用一个进程服务这个房间)，这样集群中就会有多个进程服务于这个房间。

按照默认配置，就会启动两个子进程，可以用查看webrtc_agent的子进程：

```bash
ps --ppid `cat /tmp/git/owt-docker/owt-server-4.3/dist/logs/webrtc-agent.pid`
```

或者直接ps查看`ps aux|grep 'workingNode webrtc'`：

```bash
root     41631  0.0  2.1 2882000 44100 ?       Ssl  11:35   0:00 node ./workingNode webrtc-51f1cfd00ed1e9d29a47@172.17.0.2_0 webrtc-51f1cfd00ed1e9d29a47@172.17.0.2 {"agent":{"maxProcesses":13,"prerunProcesses":2},"cluster":{"name":"owt-cluster","join_retry":60,"report_load_interval":1000,"max_load":0.85,"network_max_scale":1000,"worker":{"ip":"172.17.0.2","join_retry":60,"load":{"max":0.85,"period":1000,"item":{"name":"network","interf":"lo","max_scale":1000}}}},"capacity":{"isps":[],"regions":[]},"rabbit":{"host":"localhost","port":5672},"internal":{"ip_address":"172.17.0.2","maxport":0,"minport":0},"webrtc":{"network_interfaces":[{"name":"eth0","replaced_ip_address":"30.43.132.29","ip_address":"172.17.0.2"}],"keystorePath":"./cert/certificate.pfx","maxport":60050,"minport":60000,"stunport":0,"stunserver":"","num_workers":24,"use_nicer":false,"io_workers":1},"purpose":"webrtc"}
root     44609  0.1  2.2 2881488 46852 ?       Ssl  11:47   0:00 node ./workingNode webrtc-51f1cfd00ed1e9d29a47@172.17.0.2_1 webrtc-51f1cfd00ed1e9d29a47@172.17.0.2 {"agent":{"maxProcesses":13,"prerunProcesses":2},"cluster":{"name":"owt-cluster","join_retry":60,"report_load_interval":1000,"max_load":0.85,"network_max_scale":1000,"worker":{"ip":"172.17.0.2","join_retry":60,"load":{"max":0.85,"period":1000,"item":{"name":"network","interf":"lo","max_scale":1000}}}},"capacity":{"isps":[],"regions":[]},"rabbit":{"host":"localhost","port":5672},"internal":{"ip_address":"172.17.0.2","maxport":0,"minport":0},"webrtc":{"network_interfaces":[{"name":"eth0","replaced_ip_address":"30.43.132.29","ip_address":"172.17.0.2"}],"keystorePath":"./cert/certificate.pfx","maxport":60050,"minport":60000,"stunport":0,"stunserver":"","num_workers":24,"use_nicer":false,"io_workers":1},"purpose":"webrtc"}
```

> Note: 从上面的进程可以看出，实际上是把所有的配置参数，都通过命令行传递给了worker进程。

## Schedule

上面提到了`webrtc_agent`会作为`amqper.asRpcServer`被别的服务调用。

比如`getNode`是用户加入房间时，分配可用进程的：

1. 打开页面，进入房间。
1. 调用`getNode`，task就是任务包括（`room=5e5e24d532b3250ad3d25857`，`task=24161403438790920`）。
1. 调用`manager.getNode`，分配可用的进程，比如`nodeId=webrtc-51f1cfd00ed1e9d29a47@172.17.0.2_0`。
1. 通过消息队列返回结果，webrtc_agent就将房间调度到了这个进程上。

工作进程每隔3秒进程就会发消息，若超时则会丢弃这个进程，重新开一个进程：

```
// webrtc_agent/nodeManager.js
child.on('message', function (message) { // currently only used for sending ready message from node to agent;
  if (message === 'READY') {
      child.check_alive_interval = setInterval(function() {
        if (child.READY && (child.alive_count === 0)) {
            onNodeAbnormallyQuit && onNodeAbnormallyQuit(id, tasksOnNode(id));
            dropNode(id);
        }
      }, 3000);
```

有些任务是按房间调度的，会集中在一个进程上，比如webrtc就是按房间调度，虽然一个webrtc_agent会启动多个进程，
但是某个房间只会在一个进程上，这样在转发时避免多个进程之间传递消息。当然可以在多个节点开启webrtc_agent，
这样一个房间会有多个节点服务它，分担压力。按房间的调度方式：

```
// webrtc_agent/nodeManager.js
if (spec.consumeNodeByRoom) {
  getByRoom = findNodeUsedByRoom(nodes, task.room)
    .then((foundOne) => {
      return foundOne
    }, (notFound) => {
      return findNodeUsedByRoom(idle_nodes, task.room);
```

这些调度规则和负载衡量，和具体业务逻辑比较相关。

## workingNode

上面分析到，会启动子进程提供webrtc服务，启动参数如下：

```bash
node ./workingNode webrtc-51f1cfd00ed1e9d29a47@172.17.0.2_0 webrtc-51f1cfd00ed1e9d29a47@172.17.0.2 \
{"agent":{"maxProcesses":13,"prerunProcesses":2},"cluster":{"name":"owt-cluster","join_retry":60,\
"report_load_interval":1000,"max_load":0.85,"network_max_scale":1000,"worker":{"ip":"172.17.0.2",\
"join_retry":60,"load":{"max":0.85,"period":1000,"item":{"name":"network","interf":"lo","max_scale":1000}}}},\
"capacity":{"isps":[],"regions":[]},"rabbit":{"host":"localhost","port":5672},"internal":{"ip_address":"172.17.0.2",\
"maxport":0,"minport":0},"webrtc":{"network_interfaces":[{"name":"eth0","replaced_ip_address":"30.43.132.29",\
"ip_address":"172.17.0.2"}],"keystorePath":"./cert/certificate.pfx","maxport":60050,"minport":60000,"stunport":0,\
"stunserver":"","num_workers":24,"use_nicer":false,"io_workers":1},"purpose":"webrtc"}
```

> Note: 这些配置就是配置在`dist/webrtc_agent/agent.toml`中的。

日志是启动进程时，写入到了日志文件：

```js
      var out = fs.openSync('../logs/' + id + '.log', 'a');
      var err = fs.openSync('../logs/' + id + '.log', 'a');
```

为了了解流程，可以把最大和预留的进程改成1个，这样只会有一个webrtc进程，写一个日志文件：

```bash
# vi dist/webrtc_agent/agent.toml
[agent]
maxProcesses = 1 #default: 13
prerunProcesses = 1 #default: 2
```

比如日志文件`dist/logs/webrtc-*.log`，可以用tail看日志的内容：

```bash
tail -f dist/logs/webrtc-*
```

这个进程关键是`purpose`这个参数，这里是`purpose=webrtc`，那么会调用`webrtc_agent/webrtc/index.js`的代码：

```js
controller = require('./' + purpose)(rpcClient, rpcID, parentID, clusterWorkerIP);
var rpcAPI = (controller.rpcAPI || controller);
```

## webrtc

上面分析到，实际上workingNode会根据purpose，实际调用`webrtc_agent/webrtc/index.js`的代码。

这里很多日志是debug级别的，我们可以修改日志的级别，打印出这些日志：

```
# vi dist/webrtc_agent/log4js_configuration.json
{
  "levels": {
    "WebrtcNode": "DEBUG",
```

可以用tail看日志的内容，就包含DEBUG日志了：

```bash
tail -f dist/logs/webrtc-*
```

比如，一个人入会后(默认推流和拉流)，可以看到整个信令的处理，以及交互的过程：

```
2020-03-03 12:58:56.013  - DEBUG: WebrtcNode - publish, connectionId: 908444533627401600 connectionType: webrtc options: { controller: 'conference-a3bde0d1635ea2a57287@172.17.0.2_1',
  media:
   { audio: { source: 'mic' },
     video: { source: 'camera', parameters: [Object] } },
  formatPreference: { audio: { optional: [Array] }, video: { optional: [Array] } } }
2020-03-03 12:58:56.051  - DEBUG: WebrtcNode - onSessionSignaling, connection id: 908444533627401600 msg: { type: 'offer',
  sdp: 'v=0
2020-03-03 12:58:56.138  - DEBUG: WebrtcNode - onSessionSignaling, connection id: 908444533627401600 msg: { type: 'candidate',
  candidate:
   { candidate: 'a=candidate:285224766 1 udp 2122260223 30.43.132.29 54257 typ host generation 0 ufrag oHZy network-id 1 network-cost 10',
     sdpMid: '0',
     sdpMLineIndex: 0 } }
2020-03-03 12:58:56.152  - DEBUG: WebrtcNode - onSessionSignaling, connection id: 908444533627401600 msg: { type: 'candidate',
  candidate:
   { candidate: 'a=candidate:285224766 1 udp 2122260223 30.43.132.29 58694 typ host generation 0 ufrag oHZy network-id 1 network-cost 10',
     sdpMid: '1',
     sdpMLineIndex: 1 } }
2020-03-03 12:58:56.206  - DEBUG: WebrtcNode - subscribe, connectionId: 19607257536045750 connectionType: webrtc options: { controller: 'conference-a3bde0d1635ea2a57287@172.17.0.2_1',
  media:
   { audio: { from: '908444533627401600' },
     video: { from: '908444533627401600' } },
  formatPreference:
   { audio: { preferred: [Object], optional: [Array] },
     video: { preferred: [Object], optional: [Array] } } }
2020-03-03 12:58:56.233  - DEBUG: WebrtcNode - onSessionSignaling, connection id: 19607257536045750 msg: { type: 'offer',
  sdp: 'v=0
2020-03-03 12:58:56.264  - DEBUG: WebrtcNode - subscribe, connectionId: 908444533627401600@audio-2283a1a006e65e495e4a@172.17.0.2_1 connectionType: internal options: { controller: 'conference-a3bde0d1635ea2a57287@172.17.0.2_1',
  ip: '172.17.0.2',
  port: 38245 }
2020-03-03 12:58:56.271  - DEBUG: WebrtcNode - linkup, connectionId: 908444533627401600@audio-2283a1a006e65e495e4a@172.17.0.2_1 audioFrom: 908444533627401600 videoFrom: null
2020-03-03 12:58:56.287  - DEBUG: WebrtcNode - onSessionSignaling, connection id: 19607257536045750 msg: { type: 'candidate',
  candidate:
   { candidate: 'a=candidate:285224766 1 udp 2122260223 30.43.132.29 61289 typ host generation 0 ufrag S6n8 network-id 1 network-cost 10',
     sdpMid: '0',
     sdpMLineIndex: 0 } }
2020-03-03 12:58:56.291  - DEBUG: WebrtcNode - onSessionSignaling, connection id: 19607257536045750 msg: { type: 'candidate',
  candidate:
   { candidate: 'a=candidate:285224766 1 udp 2122260223 30.43.132.29 50053 typ host generation 0 ufrag S6n8 network-id 1 network-cost 10',
     sdpMid: '1',
     sdpMLineIndex: 1 } }
2020-03-03 12:58:56.312  - DEBUG: WebrtcNode - subscribe, connectionId: 908444533627401600@video-750a22773be07d518923@172.17.0.2_1 connectionType: internal options: { controller: 'conference-a3bde0d1635ea2a57287@172.17.0.2_1',
  ip: '172.17.0.2',
  port: 40675 }
2020-03-03 12:58:56.319  - DEBUG: WebrtcNode - linkup, connectionId: 908444533627401600@video-750a22773be07d518923@172.17.0.2_1 audioFrom: null videoFrom: 908444533627401600
2020-03-03 12:58:56.321  - DEBUG: WebrtcNode - linkup, connectionId: 19607257536045750 audioFrom: 908444533627401600 videoFrom: 908444533627401600
```

这个js如何调用webrtc的c++代码呢，在这里：

```
var addon = require('../webrtcLib/build/Release/webrtc');
```

这个文件有41MB，就是整个WebRTC打包成Nodejs能调用的库：

```
root@8d2509d377de:/tmp/git/owt-docker/owt-server-4.3# ls -lh dist/webrtc_agent/webrtcLib/build/Release/webrtc.node
-rwxr-xr-x 1 root root 41M Mar  3 09:30 dist/webrtc_agent/webrtcLib/build/Release/webrtc.node

root@8d2509d377de:/tmp/git/owt-docker/owt-server-4.3/dist/webrtc_agent# ldd webrtcLib/build/Release/webrtc.node
	linux-vdso.so.1 (0x00007ffd66ffd000)
	liblog4cxx.so.10 => /usr/lib/x86_64-linux-gnu/liblog4cxx.so.10 (0x00007f7119980000)
	libboost_thread.so.1.65.1 => /usr/lib/x86_64-linux-gnu/libboost_thread.so.1.65.1 (0x00007f711975b000)
	libboost_system.so.1.65.1 => /usr/lib/x86_64-linux-gnu/libboost_system.so.1.65.1 (0x00007f7119556000)
	libnice.so.10 => ./lib/libnice.so.10 (0x00007f7119326000)
	libstdc++.so.6 => /usr/lib/x86_64-linux-gnu/libstdc++.so.6 (0x00007f7118f9d000)
	libm.so.6 => /lib/x86_64-linux-gnu/libm.so.6 (0x00007f7118bff000)
	libgcc_s.so.1 => /lib/x86_64-linux-gnu/libgcc_s.so.1 (0x00007f71189e7000)
	libpthread.so.0 => /lib/x86_64-linux-gnu/libpthread.so.0 (0x00007f71187c8000)
	libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f71183d7000)
	/lib64/ld-linux-x86-64.so.2 (0x00007f711a6bf000)
	libapr-1.so.0 => /usr/lib/x86_64-linux-gnu/libapr-1.so.0 (0x00007f71181a2000)
	libaprutil-1.so.0 => /usr/lib/x86_64-linux-gnu/libaprutil-1.so.0 (0x00007f7117f77000)
	librt.so.1 => /lib/x86_64-linux-gnu/librt.so.1 (0x00007f7117d6f000)
	libgio-2.0.so.0 => /usr/lib/x86_64-linux-gnu/libgio-2.0.so.0 (0x00007f71179d0000)
	libgobject-2.0.so.0 => /usr/lib/x86_64-linux-gnu/libgobject-2.0.so.0 (0x00007f711777c000)
	libglib-2.0.so.0 => /usr/lib/x86_64-linux-gnu/libglib-2.0.so.0 (0x00007f7117465000)
	libuuid.so.1 => /lib/x86_64-linux-gnu/libuuid.so.1 (0x00007f711725e000)
	libdl.so.2 => /lib/x86_64-linux-gnu/libdl.so.2 (0x00007f711705a000)
	libcrypt.so.1 => /lib/x86_64-linux-gnu/libcrypt.so.1 (0x00007f7116e22000)
	libexpat.so.1 => /lib/x86_64-linux-gnu/libexpat.so.1 (0x00007f7116bf0000)
	libgmodule-2.0.so.0 => /usr/lib/x86_64-linux-gnu/libgmodule-2.0.so.0 (0x00007f71169ec000)
	libz.so.1 => /lib/x86_64-linux-gnu/libz.so.1 (0x00007f71167cf000)
	libselinux.so.1 => /lib/x86_64-linux-gnu/libselinux.so.1 (0x00007f71165a7000)
	libresolv.so.2 => /lib/x86_64-linux-gnu/libresolv.so.2 (0x00007f711638c000)
	libmount.so.1 => /lib/x86_64-linux-gnu/libmount.so.1 (0x00007f7116138000)
	libffi.so.6 => /usr/lib/x86_64-linux-gnu/libffi.so.6 (0x00007f7115f30000)
	libpcre.so.3 => /lib/x86_64-linux-gnu/libpcre.so.3 (0x00007f7115cbe000)
	libblkid.so.1 => /lib/x86_64-linux-gnu/libblkid.so.1 (0x00007f7115a71000)
```

## Nodejs NAN

上面看到，webrtc_agent是通过`webrtc_agent/webrtc/index.js`调用了C++代码：

```
var addon = require('../webrtcLib/build/Release/webrtc');
```

为了了解Nodejs如何使用C++代码，我们根据[Nodejs Addons](https://nodejs.org/api/addons.html)写了个例子[nodejs-cpp](nodejs-cpp)，
执行下面的命令运行它：

```bash
node-gyp --debug configure build && node index.js
```

> Note: 我们加了`--debug`参数，生成可以调试版本的NAN。

可以看到它的目录结构和webrtcLib的非常像：

```bash
root@d247e5015561:/tmp/git/owt-docker/nodejs-cpp# tree -h
.
|-- [  97]  binding.gyp
|-- [ 224]  build
|   |-- [ 160]  Debug
|   |   |-- [135K]  addon.node
|   |   `-- [ 128]  obj.target
|   |       |-- [  96]  addon
|   |       |   `-- [198K]  hello.o
|   |       `-- [135K]  addon.node
|   |-- [ 12K]  Makefile
|   |-- [3.6K]  addon.target.mk
|   |-- [ 113]  binding.Makefile
|   `-- [1.8K]  config.gypi
|-- [ 631]  hello.cc
`-- [ 142]  index.js
```

Nodejs调用C++的步骤：

1. `hello.cc`，是被调用的C++文件，`Initialize(Local<Object>)`函数中定义了导出的函数`hello()`，使用`NODE_MODULE(NODE_GYP_MODULE_NAME, Initialize)`导出这个Initialize函数。
1. `binding.gyp`，定义了导出的文件名`addon.node`，以及源码文件`hello.cc`，使用`node-gyp configure && node-gyp build`就可以生成Nodejs可以调用的文件`build/Release/addon.node`，本质上就是一个动态库。
1. `index.js`，导入`addon.node`，并调用函数`addon.hello()`。

> Node: Nodejs可以用NAN或N-API两种方式调用C++代码，我们这里和OWT一样是用的NAN方式，具体参考[NAN到N-API](https://xcoder.in/2017/07/01/nodejs-addon-history/)。

<a name="nodejs-nan-debug"></a>

使用gdb调试hello.cc步骤：

1. `gdb --args node index.js `，使用gdb启动node。
1. `b hello.cc:16`，在文件某行设置断点。
1. `r`，运行程序，可以看到停在了断点。
1. `bt`，可以看到调用堆栈，如下所示。

```bash
Thread 1 "node" hit Breakpoint 1, demo::Method (args=...) at ../hello.cc:16
16	  Isolate* isolate = args.GetIsolate();
(gdb) bt
#0  demo::Method (args=...) at ../hello.cc:16
#1  0x0000564ac6c14d0f in v8::internal::FunctionCallbackArguments::Call(void (*)(v8::FunctionCallbackInfo<v8::Value> const&)) ()
#2  0x0000564ac6c7db62 in ?? ()
```

<a name="nodejs-nan-owt"></a>

我们看下OWT的NAN实现，首先是`source/agent/webrtc/webrtcLib/binding.gyp`，定义了Nodejs调用的API：

```js
{
  'targets': [{
    'target_name': 'webrtc',
    'sources': [
      'addon.cc',
      'WebRtcConnection.cc',
      'erizo/src/erizo/DtlsTransport.cpp',
      '<!@(find erizo/src/erizo/dtls -name "*.cpp")',
      '../../addons/common/NodeEventRegistry.cc',
      '../../../core/owt_base/AudioFrameConstructor.cpp',
      '../../../core/rtc_adapter/VieRemb.cc' #20150508
    ],
    'cflags_cc': ['-DWEBRTC_POSIX', '-DWEBRTC_LINUX', '-DLINUX', '-DNOLINUXIF', '-DNO_REG_RPC=1', '-DHAVE_VFPRINTF=1', '-DRETSIGTYPE=void', '-DNEW_STDIO', '-DHAVE_STRDUP=1', '-DHAVE_STRLCPY=1', '-DHAVE_LIBM=1', '-DHAVE_SYS_TIME_H=1', '-DTIME_WITH_SYS_TIME_H=1'],
    'include_dirs': [
      "<!(node -e \"require('nan')\")",
      'conn_handler',
      'erizo/src/erizo',
      '../../../core/common',
      '../../../core/owt_base',
      '../../../core/rtc_adapter',
      '../../../../third_party/webrtc/src',
      '../../../../build/libdeps/build/include',
      '<!@(pkg-config glib-2.0 --cflags-only-I | sed s/-I//g)',
    ],
    'libraries': [
      '-L$(CORE_HOME)/../../build/libdeps/build/lib',
      '-lsrtp2',
      '-lnice',
      '-L$(CORE_HOME)/../../third_party/webrtc', '-lwebrtc',
    ]
  }]
}
```

> Note: 可以看到它的输出是`webrtc.node`。在`addon.cc`中定义了导出给Nodejs的API。

> Note: 可以看到它引用了`third_party/webrtc/src`的头文件和`libwebrtc.a`这个静态库。以及各个目录下的各种文件。

接着我们看下`addon.cc`中导出的API：

```cpp
void InitAll(Handle<Object> exports) {
  WebRtcConnection::Init(exports);
  MediaStream::Init(exports);
  ThreadPool::Init(exports);
  IOThreadPool::Init(exports);
  AudioFrameConstructor::Init(exports);
  AudioFramePacketizer::Init(exports);
  VideoFrameConstructor::Init(exports);
  VideoFramePacketizer::Init(exports);
}

NODE_MODULE(addon, InitAll)
```

> Note: 这里使用的是`NODE_MODULE`，也就是NAN而不是N-API方式。在InitAll函数中，调用各个模块，导出了各种API。

比如在`WebRtcConnection.cc`中导出的API：

```cpp
NAN_MODULE_INIT(WebRtcConnection::Init) {
  // Prepare constructor template
  Local<FunctionTemplate> tpl = Nan::New<FunctionTemplate>(New);
  tpl->SetClassName(Nan::New("WebRtcConnection").ToLocalChecked());
  tpl->InstanceTemplate()->SetInternalFieldCount(1);

  // Prototype
  Nan::SetPrototypeMethod(tpl, "stop", stop);
  Nan::SetPrototypeMethod(tpl, "addRemoteCandidate", addRemoteCandidate);
```

在js中是这样调用的，在`dist/webrtc_agent/webrtc/wrtcConnection.js`中：

```js
// dist/webrtc_agent/webrtc/connection.js
class Connection extends EventEmitter {
  constructor (id, threadPool, ioThreadPool, options = {}) {
    this.wrtc = this._createWrtc();
  }
  _createWrtc() {
    var wrtc = new addon.WebRtcConnection();
    return wrtc;
  }
}
exports.Connection = Connection;

// dist/webrtc_agent/webrtc/wrtcConnection.js
const { Connection } = require('./connection');
  wrtc = new Connection(wrtcId, threadPool, ioThreadPool, { ipAddresses });
        wrtc.addRemoteCandidate(msg.candidate);
```

> Note: `connection.js`中定义了js的封装，调用的就是NAN中定义的`WebRtcConnection`。

> Note: `wrtcConnection.js`中调用了`connection.js`中定义的`WebRtcConnection`，以及导出的API函数`addRemoteCandidate`等等。

