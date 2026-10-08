using System;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;

namespace CodingPlanMonitor.Services;

/// <summary>共享 HttpClient（15 秒超时，与 macOS 版一致）</summary>
internal static class Http
{
    public static readonly HttpClient Client = new() { Timeout = TimeSpan.FromSeconds(15) };

    public static async Task<(int Status, string Body)> SendAsync(HttpRequestMessage request)
    {
        using var response = await Client.SendAsync(request);
        var body = await response.Content.ReadAsStringAsync();
        return ((int)response.StatusCode, body);
    }
}

internal static class Json
{
    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNameCaseInsensitive = true,
    };
}
