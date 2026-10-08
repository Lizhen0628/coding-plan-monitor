using System;

namespace CodingPlanMonitor.Services;

/// <summary>业务错误（中文文案与 macOS 版一致）</summary>
internal sealed class QuotaServiceError : Exception
{
    private QuotaServiceError(string message) : base(message) { }

    public static QuotaServiceError MissingApiKey => new("请先在设置中填入凭证");
    public static QuotaServiceError InvalidResponse => new("响应数据格式异常");

    public static QuotaServiceError Http(int code) =>
        code is 401 or 403
            ? new QuotaServiceError($"API Key 无效或已过期（HTTP {code}）")
            : new QuotaServiceError($"请求失败（HTTP {code}）");

    public static QuotaServiceError Api(string message) => new(message);
}
