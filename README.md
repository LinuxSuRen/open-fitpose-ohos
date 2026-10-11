# Open FitPose HarmonyOS

[![build](https://github.com/linuxsuren/open-fitpose-ohos/actions/workflows/build.yml/badge.svg)](https://github.com/linuxsuren/open-fitpose-ohos/actions/workflows/build.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

开源健身/运动姿势识别鸿蒙客户端（ArkTS）：相机采集训练画面，经 WebSocket
流式上传至 [open-fitpose-server](https://github.com/linuxsuren/open-fitpose-server)，
实时绘制人体骨架、展示深蹲/俯卧撑/开合跳计数与姿态纠错提示。

## 功能

- **实时骨架叠加**：COCO 17 关键点按归一化坐标等比映射到预览画布
- **动作计数**：深蹲 / 俯卧撑 / 开合跳，计数与阶段由服务端分析
- **姿态提示**：服务端下发稳定 code，本地映射中文文案（展示与数据分离）
- **弱网韧性**：指数退避自动重连、未连接期间只缓存最新一帧

## 使用

1. 部署并启动 [open-fitpose-server](https://github.com/linuxsuren/open-fitpose-server)（默认端口 8080）
2. 安装本应用到手机（需 API 12+），授予相机权限
3. 输入服务端地址，例如 `ws://192.168.1.10:8080/api/v1/ws/pose`
   （服务端启用鉴权时再填访问令牌）
4. 点击「连接」，将手机固定在对准全身的位置，即可开始训练

## 已知限制与路线图

- ArkTS 侧暂无法直读预览 YUV 流（需 C++ NativeImage），当前基于**拍照流周期取帧**
  （约 1-2fps），快节奏动作可能漏计；预览帧直读与滑动窗口计数在路线图中
- 部分机型拍照可能伴随快门声

## 构建

DevEco Studio 打开工程直接运行，或命令行：

```bash
ohpm install
hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

要求：HarmonyOS SDK（API 12+）、Command Line Tools。

## 工程结构

```
entry/src/main/ets/
  pages/Index.ets             主页：预览/叠加画布/计数/提示/连接配置
  entryability/EntryAbility.ets
  camera/CameraController.ets 相机会话：预览 + 周期拍照取帧（base64 JPEG）
  net/PoseSocket.ets          WebSocket 客户端：重连/最新帧发送
  model/Protocol.ets          协议消息模型（契约见服务端 docs/protocol.md）
  util/Tips.ets               提示/错误 code → 中文文案
```

## 相关项目

- 服务端：[linuxsuren/open-fitpose-server](https://github.com/linuxsuren/open-fitpose-server)
- Android 客户端：[linuxsuren/open-fitpose-android](https://github.com/linuxsuren/open-fitpose-android)

## License

[Apache-2.0](LICENSE)
