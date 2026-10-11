/**
 * 服务端 WS 协议模型，契约见 open-fitpose-server docs/protocol.md。
 * ArkTS 下 JSON 解析结果以 Record 显式取值转换。
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

function asRecord(v: Object | undefined): Record<string, Object> | null {
  if (v === undefined || v === null) {
    return null;
  }
  return v as Record<string, Object>;
}

function asNumber(v: Object | undefined, def: number): number {
  if (v === undefined || v === null) {
    return def;
  }
  const n = Number(v);
  return Number.isNaN(n) ? def : n;
}

function asString(v: Object | undefined, def: string): string {
  if (v === undefined || v === null) {
    return def;
  }
  return String(v);
}

function parseStatus(an: Record<string, Object>, key: string): ActionStatus {
  const s = asRecord(an.get(key));
  if (s === null) {
    return { count: 0, stage: 'idle' };
  }
  return {
    count: asNumber(s.get('count'), 0),
    stage: asString(s.get('stage'), 'idle'),
  };
}

/** 解析服务端下行消息，无法识别时返回 null。 */
export function parseServerMessage(raw: string): SocketEvent | null {
  const msg = asRecord(JSON.parse(raw));
  if (msg === null) {
    return null;
  }
  const type = asString(msg.get('type'), '');
  if (type === 'welcome') {
    return { kind: 'welcome', provider: asString(msg.get('provider'), 'unknown') };
  }
  if (type === 'pose') {
    const kpsRaw = msg.get('keypoints');
    const keypoints: Keypoint[] = [];
    if (kpsRaw !== undefined && Array.isArray(kpsRaw)) {
      const arr = kpsRaw as Object[];
      for (let i = 0; i < arr.length; i++) {
        const k = asRecord(arr[i]);
        if (k === null) {
          continue;
        }
        keypoints.push({
          name: asString(k.get('name'), ''),
          x: asNumber(k.get('x'), 0),
          y: asNumber(k.get('y'), 0),
          score: asNumber(k.get('score'), 0),
        });
      }
    }
    let analysis: Analysis | null = null;
    const anRaw = asRecord(msg.get('analysis'));
    if (anRaw !== null) {
      analysis = {
        squat: parseStatus(anRaw, 'squat'),
        pushup: parseStatus(anRaw, 'pushup'),
        jumpingJack: parseStatus(anRaw, 'jumping_jack'),
      };
    }
    const tips: string[] = [];
    const tipsRaw = msg.get('tips');
    if (tipsRaw !== undefined && Array.isArray(tipsRaw)) {
      const arr = tipsRaw as Object[];
      for (let i = 0; i < arr.length; i++) {
        tips.push(String(arr[i]));
      }
    }
    return {
      kind: 'pose',
      result: {
        seq: asNumber(msg.get('seq'), 0),
        keypoints: keypoints,
        analysis: analysis,
        tips: tips,
      },
    };
  }
  if (type === 'error') {
    return { kind: 'error', code: asString(msg.get('code'), 'UNKNOWN') };
  }
  return null;
}

/** 构造上行 frame 消息。 */
export function buildFrameMessage(seq: number, jpegBase64: string): string {
  return JSON.stringify({
    type: 'frame',
    seq: seq,
    format: 'jpeg',
    data: jpegBase64,
  } as Record<string, Object>);
}

/** 构造上行 hello 消息。 */
export function buildHelloMessage(): string {
  return JSON.stringify({
    type: 'hello',
    protocol: 1,
    client: 'ohos',
  } as Record<string, Object>);
}
