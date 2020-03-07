# Code Video

OWT的video是MCU对于视频的处理，关键是合流和视频转码。

## Scripts

启动服务的脚本`./dist/bin/start-all.sh`，它实际上调用了如下命令启动video：

```bash
./dist/bin/daemon.sh stop video-agent &&
cd dist/video_agent && export LD_LIBRARY_PATH=./lib && node . -U video
```

video实际上由多个c++的模块组成，它们运行在nodejs video这个进程：

```bash
./videoTranscoder_sw/build/Release/videoTranscoder-sw.node
./mediaFrameMulticaster/build/Release/mediaFrameMulticaster.node
./internalIO/build/Release/internalIO.node
./videoMixer_sw/build/Release/videoMixer-sw.node
```

这些c++导出的node文件（实际上就是动态库参考[CodeNodejs](CodeNodejs)），引用了其他的so，所以需要设置`LD_LIBRARY_PATH`，否则会出现这些库找不到：

```bash
owt-server-4.3/dist/video_agent# ldd ./videoMixer_sw/build/Release/videoMixer-sw.node
	libopenh264.so.4 => not found
	libavutil.so.56 => not found
	libavcodec.so.58 => not found
	libavformat.so.58 => not found
	libavfilter.so.7 => not found
	libSvtHevcEnc.so.1 => not found

owt-server-4.3/dist/video_agent# ldd ./internalIO/build/Release/internalIO.node
	libusrsctp.so.1 => not found

owt-server-4.3/dist/video_agent# ldd ./videoTranscoder_sw/build/Release/videoTranscoder-sw.node
	libopenh264.so.4 => not found
	libavutil.so.56 => not found
	libavcodec.so.58 => not found
	libavformat.so.58 => not found
	libavfilter.so.7 => not found
	libSvtHevcEnc.so.1 => not found

owt-server-4.3/dist/video_agent# ldd videoMixer_sw/build/Release/videoMixer-sw.node
	libopenh264.so.4 => not found
	libavutil.so.56 => not found
	libavcodec.so.58 => not found
	libavformat.so.58 => not found
	libavfilter.so.7 => not found
	libSvtHevcEnc.so.1 => not found
```

> Note: 这些库都在`dist/video_agent/lib`下面，设置正确的`LD_LIBRARY_PATH`后就可以找到这些so了。

和[CodeNodejs](CodeNodejs#nodejs)中分析的一样，后面nodeManager.js会启动多个node进程，这些进程会加载上面的c++模块，而这些模块我们可以单独调试。
我们快速跟踪下，以调试模式启动：

```bash
node inspect . -U vieo
```

然后设置断点`sb('index.js', 126)`并继续，会停留在初始化nodeManager的地方：

```bash
sb(126)
c
```

接着设置断点`sb('nodeManager.js', 67)`并继续，会停留在启动video子进程的地方：

```bash
sb('nodeManager.js', 67)
c
```

查看参数`exec spawnOptions.cmd`和`exec spawnArgs`可以看到参数。相当于执行以下命令启动了子进程：

```
node ./workingNode video-e5e222e2656c19b5caa9@172.17.0.2_0 \
video-e5e222e2656c19b5caa9@172.17.0.2 {"agent":{"maxProcesses":1,"prerunProcesses":1},\
"cluster":{"name":"owt-cluster","join_retry":60,"report_load_interval":1000,\
"max_load":0.85,"worker":{"ip":"172.17.0.2","join_retry":60,"load":\
{"max":0.85,"period":1000,"item":{"name":"cpu"}}}},"rabbit":{"host":"localhost",\
"port":5672},"internal":{"ip_address":"172.17.0.2","maxport":0,"minport":0},\
"video":{"hardwareAccelerated":false,"enableBetterHEVCQuality":false,"MFE_timeout":0,\
"codecs":{"decode":["vp8","vp9","h264","h265"],"encode":["vp8","vp9","h264_CB",\
"h264_B","h265"]}},"avatar":{"location":"avatars/avatar_blue.180x180.yuv"},\
"capacity":{"video":{"decode":["vp8","vp9","h264","h265"],"encode":["vp8","vp9",\
"h264_CB","h264_B","h265"]}},"purpose":"video"}
```

## Heartbeat

启动进程后，会接收进程的消息：

```
var child = spawn(spawnOptions.cmd, spawnArgs, {}
child.on('close', function (code, signal) {}
child.on('error', function (error) {}
child.on('message', function (message) {
    child.check_alive_interval = setInterval(function() {
    }, 3000);
}
```

> Note: 在message这个心跳消息中，会设置检查的interval，如果3秒没有心跳就认为子进程有问题了，会重新开子进程。

在子进程`workingNode.js`中，会调用`process.send`给父进程发消息，也就是上面的`message`回调函数：

```bash
process.send('READY');
setInterval(() => {
    process.send('IMOK');
}, 1000);
```

> Note: 连接到RabbitMQ后，就会给父进程发送`READY`消息，然后每隔1秒发送一条`IMOK`的心跳消息。

## Load Balancer

启动video-agent后，会加入集群，指定负载相关函数：

```bash
worker = clusterWorker({
    purpose: myPurpose, // video
    clusterName: config.cluster.name, // owt-cluster
    info: {
        ip: config.cluster.worker.ip, // 172.17.0.2
        max_load: config.cluster.worker.load.max, // 0.85
        capacity: config.capacity // video.decode['vp8','vp9','h264','h265'],
                                // video.encode['vp8','vp9','h264_CB','h264_B','h265']
    },
    onOverload: overload, // 不做什么
    loadCollection: config.cluster.worker.load // 定义在configLoader.js
});
```

负载的配置是在`configLoader.js`：

```js
config.cluster.worker.load = config.cluster.worker.load || {};
config.cluster.worker.load.max = config.cluster.max_load || 0.85;
config.cluster.worker.load.period = config.cluster.report_load_interval || 1000;
config.cluster.worker.load.item = {
  name: 'cpu'
};
```

可见，video的负载是以`cpu`为计算，每隔1秒汇报一次，最高负载0.85。

## Schedule

video-agent通过RabbitMQ接收任务，定义在`index.js`中：

```
var rpcAPI = function (worker) {
    return {
        getNode: function(task, callback) {
          if (manager) {
            return manager.getNode(task).then((nodeId) => {
              callback('callback', nodeId);
```

它调用了`nodeManager.js`中的获取进程的函数：

```
that.getNode = (task) => {
    // room: '5e630faec04d6863f75db2d4', task: '98295945257153838348'
    if (spec.consumeNodeByRoom) { // false
    } else {
      getByRoom = Promise.reject('Not found');
    }

return getByRoom
  .then((foundOne) => {
    return foundOne;
  }, (notFound) => {
    return pickInIdle(); // 没有找到，就找一个空闲的
  })
  .then((nodeId) => {
    return waitTillNodeReady(nodeId, 1500/*FIXME: Use a more reasonable timeout value instead of hard coding*/);
  }).then((nodeId) => {
    addTask(nodeId, task);
    return nodeId;
  });
};
```

由于video并不是按房间(consumeNodeByRoom)调度的，所以会找一个空闲的`pickInIdle`：

```
  let pickInIdle = () => {
    return new Promise((resolve, reject) => {
      let node_id = idle_nodes.shift();
      nodes.push(node_id);
      setTimeout(() => {
        if ((spec.maxNodeNum < 0) || ((nodes.length + idle_nodes.length) < spec.maxNodeNum)) {
          fillNodes();
        } else if (spec.reuseNode) { // false
          idle_nodes.push(nodes.shift());
        }
      }, 0);

      resolve(node_id); // video-eed09f68e5bc1a5ff382@172.17.0.2_1
    });
  };
```

这里会把目前空闲的video返回，然后重新开启一个新的video进程（若还没达到maxNodeNum上限）。

```
2020-03-07 03:54:40.466  - DEBUG: AmqpClient - New message received { method: 'getNode',
  args:
   [ { room: '5e631598824dfb04091f1e59',
       task: '72122114062012276925' } ],
  corrID: 4,
  replyTo: 'amq.gen-LWAiGFWFEBtxk9tdTJZoLA' }
2020-03-07 03:54:40.467  - DEBUG: NodeManager - getNode, task: { room: '5e631598824dfb04091f1e59',
  task: '72122114062012276925' }
2020-03-07 03:54:40.471  - DEBUG: NodeManager - not found existing node
2020-03-07 03:54:40.473  - DEBUG: NodeManager - got nodeId: video-d683f43dffd8b4faf936@172.17.0.2_0
2020-03-07 03:54:40.475  - DEBUG: NodeManager - node video-d683f43dffd8b4faf936@172.17.0.2_0 is ready
2020-03-07 03:54:40.494  - DEBUG: NodeManager - launchNode, id: video-d683f43dffd8b4faf936@172.17.0.2_1
```

> Note: MCU模式下，第一个人进来订阅的就已经是video转码的流，第二个人进来订阅的同样的流，所以不会再启动一个video转一次码。

## VideoNode

上面分析了调度过程，最终一个task分配到video node后，我们可以开启video-agent的日志来看这个过程：

```
# vi dist/video_agent/log4js_configuration.json + 18
    "LayoutProcessor": "DEBUG",
    "VideoNode": "DEBUG",
```

启动时，video node进程打开的文件如下：

```
root@e6831daf9453:/tmp/git/owt-docker/owt-server-4.3# lsof -p 1139
COMMAND  PID USER   FD      TYPE             DEVICE SIZE/OFF       NODE NAME
node    1139 root  cwd       DIR               0,80     1184 8638807168 /tmp/git/owt-docker/owt-server-4.3/dist/video_agent
node    1139 root    0r      CHR                1,3      0t0    1683075 /dev/null
node    1139 root    1w      REG               0,80      568 8639223308 /tmp/git/owt-docker/owt-server-4.3/dist/logs/video-308f3fc586f3c6cd8873@172.17.0.2_0.log
node    1139 root    2w      REG               0,80      568 8639223308 /tmp/git/owt-docker/owt-server-4.3/dist/logs/video-308f3fc586f3c6cd8873@172.17.0.2_0.log
node    1139 root    3u     unix 0x0000000000000000      0t0    1685628 type=STREAM
node    1139 root    4u  a_inode               0,13        0      12074 [eventpoll]
node    1139 root    5r     FIFO               0,12      0t0    1686612 pipe
node    1139 root    6w     FIFO               0,12      0t0    1686612 pipe
node    1139 root    7r     FIFO               0,12      0t0    1686613 pipe
node    1139 root    8w     FIFO               0,12      0t0    1686613 pipe
node    1139 root    9u  a_inode               0,13        0      12074 [eventfd]
node    1139 root   10r      CHR                1,3      0t0    1683075 /dev/null
node    1139 root   11u     IPv4            1687667      0t0        TCP localhost:38670->localhost:amqp (ESTABLISHED)
```

> Note: 0,1,2是标准输入输出，定向到了日志文件。11是和RabbitMQ建立的TCP连接。

这样第一个人进入房间时，就会启动video node的进程，日志如下：

```
####### vi dist/video_agent/video/index.js +361
2020-03-07 04:14:36.116  - DEBUG: VideoNode - initEngine, videoConfig: {"layout":{"templates":[{"region":[{"id":"1"...
####### vi source/agent/video/videoMixer/VideoMixer.cpp +66
2020-03-07 04:14:36,124  - INFO: mcu.media.VideoMixer - Init maxInput(16), rootSize(640, 480), bgColor(16, 128, 128)
####### vi dist/video_agent/video/index.js +403
2020-03-07 04:14:36.128  - DEBUG: VideoNode - Video engine init OK, supported_codecs: { decode: [ 'vp8', 'vp9', 'h264', 'h265' ],
  encode: [ 'vp8', 'vp9', 'h264_CB', 'h264_B', 'h265' ] }

2020-03-07 04:14:36.329  - DEBUG: VideoNode - generate, codec: vp8 resolution: { height: 480, width: 640 } framerate: 24 bitrate: unspecified keyFrameInterval: 100
2020-03-07 04:14:36.335  - DEBUG: VideoNode - addOutput: codec vp8 resolution: { height: 480, width: 640 } framerate: 24 bitrate: 665.5999999999999 keyFrameInterval: 100
2020-03-07 04:14:36.358  - DEBUG: VideoNode - addOutput ok, stream_id: 846206823613141500

2020-03-07 04:14:36.408  - DEBUG: VideoNode - subscribe, connectionId: 846206823613141500@webrtc-799819c55bf3c48359a0@172.17.0.2_0 connectionType: internal options: { controller: 'conference-c281c7e712053a6e671c@172.17.0.2_8',
  ip: '172.17.0.2',
  port: 45201 }
2020-03-07 04:14:36.424  - DEBUG: VideoNode - linkup, connectionId: 846206823613141500@webrtc-799819c55bf3c48359a0@172.17.0.2_0 video_stream_id: 846206823613141500
2020-03-07 04:14:36.434  - DEBUG: VideoNode - forceKeyFrame, stream_id: 846206823613141500

2020-03-07 04:14:37.076  - DEBUG: VideoNode - publish, stream_id: 381316705155855500 stream_type: internal options: { controller: 'conference-c281c7e712053a6e671c@172.17.0.2_8',
  publisher: 'RWxUX5bGzGfl3IocAAAN',
  audio: false,
  video: { codec: 'vp8' },
  ip: '172.17.0.2',
  port: 0 }
2020-03-07 04:14:37.079  - DEBUG: VideoNode - publish 1, inputs.length: 0 maxInputNum: 16
2020-03-07 04:14:37.081  - DEBUG: VideoNode - add input 381316705155855500
2020-03-07 04:14:37.092  - DEBUG: VideoNode - layoutChange [ { input: 0,
    region: Region { id: '1', shape: 'rectangle', area: [Object] } } ]
2020-03-07 04:14:37.105  - DEBUG: VideoNode - addInput ok, stream_id: 381316705155855500 codec: vp8 options: { controller: 'conference-c281c7e712053a6e671c@172.17.0.2_8',
  publisher: 'RWxUX5bGzGfl3IocAAAN',
  audio: false,
  video: { codec: 'vp8' },
  ip: '172.17.0.2',
  port: 0 }
```

同时，还会和webrtc-agent建立TCP连接，传输数据：

```
root@e6831daf9453:/tmp/git/owt-docker/owt-server-4.3# lsof -p 1139
COMMAND  PID USER   FD      TYPE             DEVICE SIZE/OFF       NODE NAME
node    1139 root   24u     IPv4            1732369      0t0        TCP e6831daf9453:46560->e6831daf9453:42979 (ESTABLISHED)
node    1139 root   28u     IPv4            1735017      0t0        TCP *:42003 (LISTEN)
node    1139 root   29u     IPv4            1733908      0t0        TCP e6831daf9453:42003->e6831daf9453:43630 (ESTABLISHED)

root@e6831daf9453:/tmp/git/owt-docker/owt-server-4.3# netstat -anp|grep 42979
tcp        0      0 0.0.0.0:42979           0.0.0.0:*               LISTEN      1539/node
tcp        0      0 172.17.0.2:46560        172.17.0.2:42979        ESTABLISHED 1139/node
tcp        0      0 172.17.0.2:42979        172.17.0.2:46560        ESTABLISHED 1539/node

root@e6831daf9453:/tmp/git/owt-docker/owt-server-4.3# netstat -anp|grep 42003
tcp        0      0 0.0.0.0:42003           0.0.0.0:*               LISTEN      1139/node
tcp        0      0 172.17.0.2:42003        172.17.0.2:43630        ESTABLISHED 1139/node
tcp        0      0 172.17.0.2:43630        172.17.0.2:42003        ESTABLISHED 1539/node

root@e6831daf9453:/tmp/git/owt-docker/owt-server-4.3# ps aux|grep 1539
root      1539  7.0  2.9 3079952 59228 ?       Ssl  05:02   1:09 node ./workingNode webrtc-cd8145aa9503b6c79d39@172.17.0.2_0
```

> Note: webrtc(PID=1539,PORT=42979)侦听了这个端口，video(PID=1139,PORT=46560)连接到了这个端口。video从webrtc取第一个人推上来的流。

> Note: video(PID=1139,PORT=42003)侦听了端口，webrtc(PID=1539,PORT=43630)连接到了这个端口。webrtc从video取合并的流。

> Note: `roomController.js`的函数getVideoStream中，会判断是调用mixer还是transcoder，然后给video-agent发送消息。

第二个人进入房间时，这个video node会订阅它的流并合并：

```
2020-03-07 04:20:07.411  - DEBUG: VideoNode - generate, codec: vp8 resolution: { height: 480, width: 640 } framerate: 24 bitrate: unspecified keyFrameInterval: 100
2020-03-07 04:20:07.527  - DEBUG: VideoNode - forceKeyFrame, stream_id: 846206823613141500

2020-03-07 04:20:07.952  - DEBUG: VideoNode - publish, stream_id: 658664324543501000 stream_type: internal options: { controller: 'conference-c281c7e712053a6e671c@172.17.0.2_8',
  publisher: 'J-keGdJVYxNGzdSPAAAO',
  audio: false,
  video: { codec: 'vp8' },
  ip: '172.17.0.2',
  port: 0 }
2020-03-07 04:20:07.956  - DEBUG: VideoNode - publish 1, inputs.length: 1 maxInputNum: 16
2020-03-07 04:20:07.986  - DEBUG: VideoNode - add input 658664324543501000
2020-03-07 04:20:08.038  - DEBUG: VideoNode - layoutChange [ { input: 0,
    region: Region { id: '1', shape: 'rectangle', area: [Object] } },
  { input: 1,
    region: Region { id: '2', shape: 'rectangle', area: [Object] } },
  { region: Region { id: '3', shape: 'rectangle', area: [Object] } },
  { region: Region { id: '4', shape: 'rectangle', area: [Object] } } ]
2020-03-07 04:20:08.090  - DEBUG: VideoNode - addInput ok, stream_id: 658664324543501000 codec: vp8 options: { controller: 'conference-c281c7e712053a6e671c@172.17.0.2_8',
  publisher: 'J-keGdJVYxNGzdSPAAAO',
  audio: false,
  video: { codec: 'vp8' },
  ip: '172.17.0.2',
  port: 0 }
```

查看TCP连接的变化：

```
node    1139 root   33u     IPv4            1749431      0t0        TCP *:38291 (LISTEN)
node    1139 root   34u     IPv4            1748334      0t0        TCP e6831daf9453:38291->e6831daf9453:56992 (ESTABLISHED)

root@e6831daf9453:/tmp/git/owt-docker/owt-server-4.3# netstat -anp|grep 38291
tcp        0      0 0.0.0.0:38291           0.0.0.0:*               LISTEN      1139/node
tcp        0      0 172.17.0.2:56992        172.17.0.2:38291        ESTABLISHED 1539/node
tcp        0      0 172.17.0.2:38291        172.17.0.2:56992        ESTABLISHED 1139/node
```

> Note: video(PID=1139,PORT=38291)侦听了端口，webrtc(PID=1539,PORT=56992)连接到了这个端口。webrtc从video取合并的流，每个人的流都会从video取一次。

启动GDB调试，并Attach调试Video Agent的进程：

```bash
gdb --pid `ps aux|grep video|grep workingNode|awk '{print $2}'`
```