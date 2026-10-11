/**
 * 服务端提示/错误 code → 本地文案。
 * 服务端只下发稳定 code（展示与数据分离），未知 code 走兜底文案。
 */
export class Tips {
  private static readonly TIP_MAP: Record<string, string> = {
    'SQUAT_NOT_DEEP_ENOUGH': '下蹲深度不足，再蹲低一些',
    'KNEE_OVER_TOE': '膝盖超过脚尖，注意收膝',
    'BACK_NOT_STRAIGHT': '躯干过度前倾，挺直腰背',
    'BODY_NOT_STRAIGHT': '身体未呈一条直线，收紧核心',
    'ARMS_NOT_FULLY_RAISED': '手臂未完全打开举过头顶',
  };

  private static readonly ERROR_MAP: Record<string, string> = {
    'UNAUTHORIZED': '访问令牌不正确，请检查服务端鉴权配置',
    'FRAME_TOO_LARGE': '画面过大，服务端已拒绝，请降低分辨率',
    'INFERENCE_FAILED': '服务端推理暂不可用，正在自动重试',
  };

  static format(tips: string[]): string {
    if (tips.length === 0) {
      return '动作标准，继续保持';
    }
    const texts: string[] = [];
    for (const code of tips) {
      texts.push(Tips.TIP_MAP[code] ?? '注意动作规范');
    }
    return texts.join('\n');
  }

  static errorText(code: string): string {
    return Tips.ERROR_MAP[code] ?? '注意动作规范';
  }
}
