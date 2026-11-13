#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <morecolors>

#define MAX_MSGS 32
#define MAX_MSG_LEN 256

char g_Messages[MAX_MSGS][MAX_MSG_LEN];
char g_MapMessage[MAX_MSG_LEN];
int g_MessageCount;

public Plugin myinfo =
{
    name = "Round End Chat Messages",
    author = "MindfulProtons, random",
    description = "Displays configured chat messages after each round.",
    version = "1.0"
};

public void OnPluginStart()
{
    CCheckTrie();

    HookEvent("teamplay_round_win", Event_RoundEnd);

    LoadCustomColors();
    LoadMessages();
    LoadMapMessage();

    RegAdminCmd("sm_roundmessages_reload", Command_Reload, ADMFLAG_CONFIG,
        "Reload round-end chat messages and custom colors.");
}

public Action Command_Reload(int client, int args)
{
    LoadCustomColors();
    LoadMessages();
    LoadMapMessage();

    ReplyToCommand(client, "[RoundEndMessages] Configuration reloaded.");
    return Plugin_Handled;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    LoadMapMessage();

    if (g_MapMessage[0] != '\0' || g_MessageCount > 0)
    {
        CreateTimer(1.0, Timer_DisplayMessage);
    }
}

public Action Timer_DisplayMessage(Handle timer)
{
    if (g_MapMessage[0] != '\0')
    {
        PrintChatMessageAll("%s", g_MapMessage);
    }
    else if (g_MessageCount > 0)
    {
        int index = GetRandomInt(0, g_MessageCount - 1);
        PrintChatMessageAll("%s", g_Messages[index]);
    }

    return Plugin_Stop;
}

void LoadCustomColors()
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/round-end-messages.cfg");

    KeyValues kv = new KeyValues("RoundEndMessages");
    if (!kv.ImportFromFile(path))
    {
        LogError("RoundEndMessages: failed to read %s", path);
        delete kv;
        return;
    }

    if (!kv.JumpToKey("CustomColors", false))
    {
        LogError("RoundEndMessages: CustomColors block missing in %s", path);
        delete kv;
        return;
    }

    if (kv.GotoFirstSubKey(false))
    {
        char colorName[64], hex[7];

        do
        {
            kv.GetSectionName(colorName, sizeof(colorName));
            kv.GetString(NULL_STRING, hex, sizeof(hex));
            SetTrieValue(CTrie, colorName, StringToInt(hex, 16));
        }
        while (kv.GotoNextKey(false));
    }

    delete kv;
    PrintToServer("[RoundEndMessages] Loaded custom colors.");
}

void LoadMessages()
{
    g_MessageCount = 0;

    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/round-end-messages.cfg");

    KeyValues kv = new KeyValues("RoundEndMessages");
    if (!kv.ImportFromFile(path))
    {
        LogError("RoundEndMessages: failed to read %s", path);
        delete kv;
        return;
    }

    if (!kv.JumpToKey("Messages", false))
    {
        LogError("RoundEndMessages: Messages block missing in %s", path);
        delete kv;
        return;
    }

    if (kv.GotoFirstSubKey(false))
    {
        do
        {
            if (g_MessageCount >= MAX_MSGS)
            {
                LogError("RoundEndMessages: maximum of %d messages reached; extra messages ignored.", MAX_MSGS);
                break;
            }

            char message[MAX_MSG_LEN];
            kv.GetString(NULL_STRING, message, sizeof(message), "");

            if (message[0] == '\0')
            {
                continue;
            }

            strcopy(g_Messages[g_MessageCount], MAX_MSG_LEN, message);
            g_MessageCount++;
        }
        while (kv.GotoNextKey(false));
    }

    delete kv;
    PrintToServer("[RoundEndMessages] Loaded %d messages.", g_MessageCount);
}

void PrintChatMessageAll(const char[] message, any...)
{
    CCheckTrie();

    char buffer[MAX_BUFFER_LENGTH], formatted[MAX_BUFFER_LENGTH];

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsClientInGame(client) || CSkipList[client])
        {
            CSkipList[client] = false;
            continue;
        }

        Format(buffer, sizeof(buffer), "\x01%s", message);
        VFormat(formatted, sizeof(formatted), buffer, 2);
        CReplaceColorCodes(formatted);
        CSendMessage(client, formatted);
    }
}


void LoadMapMessage()
{
    g_MapMessage[0] = '\0';

    char map[PLATFORM_MAX_PATH];
    GetCurrentMap(map, sizeof(map));

    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/round-end-messages.cfg");

    KeyValues kv = new KeyValues("RoundEndMessages");

    if (!kv.ImportFromFile(path))
    {
        LogError("RoundEndMessages: failed to read %s", path);
        delete kv;
        return;
    }

    if (kv.JumpToKey("MapMessages", false))
    {
        if (kv.JumpToKey(map, false))
        {
            kv.GetString("message", g_MapMessage, sizeof(g_MapMessage));
        }
        else
        {
            char sectionName[PLATFORM_MAX_PATH];

            if (kv.GotoFirstSubKey(false))
            {
                do
                {
                    kv.GetSectionName(sectionName, sizeof(sectionName));

                    if (StrEqual(sectionName, map, false))
                    {
                        kv.GetString("message", g_MapMessage, sizeof(g_MapMessage));
                        break;
                    }
                }
                while (kv.GotoNextKey(false));
            }
        }
    }

    if (g_MapMessage[0] != '\0')
    {
        PrintToServer("[RoundEndMessages] Loaded map-specific message for: %s", map);
    }
    else
    {
        PrintToServer("[RoundEndMessages] No map-specific message configured for: %s", map);
    }

    delete kv;
}
