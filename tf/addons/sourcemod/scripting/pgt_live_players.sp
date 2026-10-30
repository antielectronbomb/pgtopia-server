/**
 * P.G.Topia Live Players - TF2/SourceMod server-side publisher.
 *
 * Sends an authenticated, form-encoded HTTPS POST to the P.G.Topia web backend.
 * The web backend should expose the result to any number of websites.
 * Requires the SteamWorks SourceMod extension and its steamworks.inc for compilation.
 * Does not expose a public HTTP listener or disclose player names/IP addresses.
 */
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <SteamWorks>

#define PLUGIN_VERSION "1.0.0"

public Plugin myinfo =
{
    name = "P.G.Topia Live Players",
    author = "P.G.Topia",
    description = "Pushes live TF2 player counts to a website HTTPS endpoint",
    version = PLUGIN_VERSION,
    url = "https://pgtopia.beer"
};

ConVar g_Endpoint;
ConVar g_Token;
ConVar g_ServerId;
ConVar g_Interval;

bool g_InFlight = false;
bool g_Dirty = true;
int g_Sequence = 0;
int g_Failures = 0;
int g_LastSuccessUnix = 0;
float g_LastAttemptAt = -10000.0;
float g_RetryAfter = 0.0;
char g_SessionId[40];

public void OnPluginStart()
{
    CreateConVar("sm_pgt_live_version", PLUGIN_VERSION,
        "P.G.Topia Live Players plugin version", FCVAR_NOTIFY | FCVAR_DONTRECORD);

    g_Endpoint = CreateConVar("sm_pgt_live_endpoint", "",
        "Full HTTPS URL of website's private count-ingest POST endpoint", FCVAR_PROTECTED);
    g_Token = CreateConVar("sm_pgt_live_token", "",
        "Shared secret to send in X-PGT-Token header (24+ characters)", FCVAR_PROTECTED);
    g_ServerId = CreateConVar("sm_pgt_live_server_id", "pgtopia-tf2",
        "Website-defined server ID (letters, digits, _ and - only)");
    g_Interval = CreateConVar("sm_pgt_live_interval", "5.0",
        "Normal heartbeat in seconds", _, true, 3.0, true, 60.0);

    g_Endpoint.AddChangeHook(OnSettingChanged);
    g_Token.AddChangeHook(OnSettingChanged);
    g_ServerId.AddChangeHook(OnSettingChanged);
    g_Interval.AddChangeHook(OnSettingChanged);

    RegAdminCmd("sm_pgt_live_status", Command_Status, ADMFLAG_ROOT,
        "Display publisher status and current counts (never prints secret)");
    RegAdminCmd("sm_pgt_live_send", Command_Send, ADMFLAG_ROOT,
        "Request an immediate player-count update");

    Format(g_SessionId, sizeof(g_SessionId), "%d-%d", GetTime(), GetRandomInt(100000, 999999));
    AutoExecConfig(true, "pgt_live_players");

    // No NO_MAPCHANGE flag: maintain heartbeats across map changes.
    CreateTimer(1.0, Timer_Heartbeat, _, TIMER_REPEAT);
}

public void OnConfigsExecuted()
{
    g_Dirty = true;
}

public void OnMapStart()
{
    g_Dirty = true;
}

public void OnClientPutInServer(int client)
{
    g_Dirty = true;
}

public void OnClientDisconnect_Post(int client)
{
    g_Dirty = true;
    // Publishing zero immediately avoids leaving a stale nonzero count when
    // the server goes idle/hibernates before the next heartbeat can execute.
    if (CountHumans() == 0)
    {
        TryPublish(true);
    }
}

public void OnSettingChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    g_Dirty = true;
    g_RetryAfter = 0.0;
}

public Action Timer_Heartbeat(Handle timer)
{
    TryPublish(false);
    return Plugin_Continue;
}

public Action Command_Send(int client, int args)
{
    g_Dirty = true;
    // Do not defeat the in-flight lock or backoff after network failures.
    TryPublish(true);
    ReplyToCommand(client, "[PGT Live] Publish requested; use sm_pgt_live_status to see delivery state.");
    return Plugin_Handled;
}

public Action Command_Status(int client, int args)
{
    int humans, bots;
    CountPlayers(humans, bots);
    int age = (g_LastSuccessUnix == 0) ? -1 : GetTime() - g_LastSuccessUnix;
    char endpoint[512], token[256], serverId[64];
    g_Endpoint.GetString(endpoint, sizeof(endpoint));
    g_Token.GetString(token, sizeof(token));
    g_ServerId.GetString(serverId, sizeof(serverId));
    bool configured = (StrContains(endpoint, "https://", false) == 0 &&
                       IsValidServerId(serverId) && IsValidToken(token));
    ReplyToCommand(client,
        "[PGT Live] Configured: %d | Humans: %d | Bots: %d | Total: %d/%d | in-flight: %d | failures: %d | last success (s ago): %d",
        configured, humans, bots, humans + bots, MaxClients, g_InFlight, g_Failures, age);
    return Plugin_Handled;
}

int CountHumans()
{
    int humans, bots;
    CountPlayers(humans, bots);
    return humans;
}

void CountPlayers(int &humans, int &bots)
{
    humans = 0;
    bots = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsClientSourceTV(i) || IsClientReplay(i))
            continue;
        if (IsFakeClient(i))
            bots++;
        else
            humans++;
    }
}

bool IsValidServerId(const char[] value)
{
    int length = strlen(value);
    if (length < 1 || length > 48)
        return false;
    for (int i = 0; i < length; i++)
    {
        int c = value[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') || c == '_' || c == '-'))
            return false;
    }
    return true;
}

bool IsValidToken(const char[] value)
{
    int length = strlen(value);
    if (length < 24 || length > 192)
        return false;
    // Header must never contain control characters (including CR and LF).
    for (int i = 0; i < length; i++)
    {
        if (value[i] < 33 || value[i] > 126)
            return false;
    }
    return true;
}

void MarkFailure(const char[] reason, int status = 0)
{
    g_Failures++;
    g_Dirty = true;
    float delay = float(g_Failures * 5);
    if (delay > 60.0)
        delay = 60.0;
    g_RetryAfter = GetEngineTime() + delay;
    if (g_Failures == 1 || (g_Failures % 6) == 0)
    {
        LogError("[PGT Live] Publish failed: %s (HTTP %d); retry in %.0fs (failure #%d)",
            reason, status, delay, g_Failures);
    }
}

bool SetIntegerField(Handle request, const char[] field, int value)
{
    char number[24];
    IntToString(value, number, sizeof(number));
    return SteamWorks_SetHTTPRequestGetOrPostParameter(request, field, number);
}

void TryPublish(bool urgent)
{
    if (g_InFlight)
        return;

    float now = GetEngineTime();
    if (now < g_RetryAfter)
        return;

    float elapsed = now - g_LastAttemptAt;
    if (!urgent && !g_Dirty && elapsed < g_Interval.FloatValue)
        return;
    if (!urgent && g_Dirty && elapsed < 1.0)
        return;

    char endpoint[512], token[256], serverId[64];
    g_Endpoint.GetString(endpoint, sizeof(endpoint));
    g_Token.GetString(token, sizeof(token));
    g_ServerId.GetString(serverId, sizeof(serverId));

    // Ignore unconfigured plugin without creating a flood of error logs.
    if (endpoint[0] == '\0' || token[0] == '\0')
        return;

    if (StrContains(endpoint, "https://", false) != 0 || !IsValidServerId(serverId) || !IsValidToken(token))
    {
        // Settings are invalid; log on explicit administrative check only.
        return;
    }

    Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, endpoint);
    if (request == INVALID_HANDLE)
    {
        g_LastAttemptAt = now;
        MarkFailure("could not create HTTP request");
        return;
    }

    int humans, bots;
    CountPlayers(humans, bots);
    char mapName[128];
    GetCurrentMap(mapName, sizeof(mapName));

    bool ok = true;
    ok = ok && SteamWorks_SetHTTPRequestHeaderValue(request, "X-PGT-Token", token);
    ok = ok && SteamWorks_SetHTTPRequestHeaderValue(request, "Accept", "application/json");
    ok = ok && SteamWorks_SetHTTPRequestRequiresVerifiedCertificate(request, true);
    ok = ok && SteamWorks_SetHTTPRequestNetworkActivityTimeout(request, 8);
    ok = ok && SteamWorks_SetHTTPRequestAbsoluteTimeoutMS(request, 12000);
    ok = ok && SteamWorks_SetHTTPRequestGetOrPostParameter(request, "server_id", serverId);
    ok = ok && SteamWorks_SetHTTPRequestGetOrPostParameter(request, "session_id", g_SessionId);
    ok = ok && SteamWorks_SetHTTPRequestGetOrPostParameter(request, "map", mapName);
    ok = ok && SetIntegerField(request, "player_count", humans + bots);
    ok = ok && SetIntegerField(request, "human_players", humans);
    ok = ok && SetIntegerField(request, "bot_players", bots);
    ok = ok && SetIntegerField(request, "max_players", MaxClients);
    ok = ok && SetIntegerField(request, "unix_time", GetTime());
    ok = ok && SetIntegerField(request, "sequence", ++g_Sequence);
    ok = ok && SteamWorks_SetHTTPCallbacks(request, OnHTTPComplete);

    g_LastAttemptAt = now;
    if (!ok)
    {
        delete request;
        MarkFailure("could not prepare HTTP request");
        return;
    }

    g_InFlight = true;
    if (!SteamWorks_SendHTTPRequest(request))
    {
        g_InFlight = false;
        delete request;
        MarkFailure("could not dispatch HTTP request");
        return;
    }
    g_Dirty = false;
}

public void OnHTTPComplete(Handle request, bool failure, bool requestSuccessful, EHTTPStatusCode status)
{
    g_InFlight = false;
    int code = view_as<int>(status);
    if (!failure && requestSuccessful && code >= 200 && code < 300)
    {
        if (g_Failures != 0)
            LogMessage("[PGT Live] HTTPS publishing recovered");
        g_Failures = 0;
        g_LastSuccessUnix = GetTime();
        g_RetryAfter = 0.0;
    }
    else
    {
        MarkFailure("transport or non-2xx response", code);
    }
    delete request;
}
