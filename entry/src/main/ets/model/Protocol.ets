/**
 * 服务端 WS 协议模型，契约见 open-fitpose-server docs/protocol.md。
 * JSON 解析参照 ArkTS 规范：JSON.parse 结果直接 as 到显式接口。
 */

export interface Keypoint {
  name: string;
  x: number;
  y: number;
  score: number;
}

export interface ActionStatus {
  count: number;
  stage: string;
}

export interface Analysis {
  squat: ActionStatus;
  pushup: ActionStatus;
  jumpingJack: ActionStatus;
}

export interface PoseResult {
  seq: number;
  keypoints: Keypoint[];
  analysis: Analysis | null;
  tips: string[];
}

export interface SocketEvent {
  kind: string; // welcome | pose | error
  provider?: string;
  result?: PoseResult;
  code?: string;
}

// ---- JSON 原始结构（字段与协议一一对应，均为可选） ----

interface RawKeypoint {
  name?: string;
  x?: number;
  y?: number;
  score?: number;
}

interface RawStatus {
  count?: number;
  stage?: string;
}

interface RawAnalysis {
  squat?: RawStatus;
  pushup?: RawStatus;
  jumping_jack?: RawStatus;
}

interface RawMessage {
  type?: string;
  provider?: string;
  seq?: number;
  keypoints?: RawKeypoint[];
  analysis?: RawAnalysis;
  tips?: string[];
  code?: string;
}

// ---- 上行消息（显式类，满足 ArkTS 对象字面量限制） ----

class FrameMessage {
  type: string = 'frame';
  seq: number = 0;
  format: string = 'jpeg';
  data: string = '';
}

class HelloMessage {
  type: string = 'hello';
  protocol: number = 1;
  client: string = 'ohos';
}

function toStatus(raw: RawStatus | undefined): ActionStatus {
  if (raw === undefined) {
    return { count: 0, stage: 'idle' };
  }
  return {
    count: raw.count ?? 0,
    stage: raw.stage ?? 'idle',
  };
}

/** 解析服务端下行消息，无法识别时返回 null。 */
export function parseServerMessage(raw: string): SocketEvent | null {
  let msg: RawMessage;
  try {
    msg = JSON.parse(raw) as RawMessage;
  } catch (e) {
    return null;
  }
  const type = msg.type ?? '';
  if (type === 'welcome') {
    return { kind: 'welcome', provider: msg.provider ?? 'unknown' };
  }
  if (type === 'pose') {
    const keypoints: Keypoint[] = [];
    const rawKps = msg.keypoints ?? [];
    for (const k of rawKps) {
      keypoints.push({
        name: k.name ?? '',
        x: k.x ?? 0,
        y: k.y ?? 0,
        score: k.score ?? 0,
      });
    }
    let analysis: Analysis | null = null;
    if (msg.analysis !== undefined) {
      analysis = {
        squat: toStatus(msg.analysis.squat),
        pushup: toStatus(msg.analysis.pushup),
        jumpingJack: toStatus(msg.analysis.jumping_jack),
      };
    }
    return {
      kind: 'pose',
      result: {
        seq: msg.seq ?? 0,
        keypoints: keypoints,
        analysis: analysis,
        tips: msg.tips ?? [],
      },
    };
  }
  if (type === 'error') {
    return { kind: 'error', code: msg.code ?? 'UNKNOWN' };
  }
  return null;
}

/** 构造上行 frame 消息。 */
export function buildFrameMessage(seq: number, jpegBase64: string): string {
  const m = new FrameMessage();
  m.seq = seq;
  m.data = jpegBase64;
  return JSON.stringify(m);
}

/** 构造上行 hello 消息。 */
export function buildHelloMessage(): string {
  return JSON.stringify(new HelloMessage());
}
