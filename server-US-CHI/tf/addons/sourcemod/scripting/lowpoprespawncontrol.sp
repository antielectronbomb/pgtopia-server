#pragma semicolon 1

#include <sourcemod>

ConVar mpDisableRespawnTimesConVar;
ConVar sourceTVConVar;
ConVar lprcTriggerBelowConVar;
int originalDisableRespawnTimes = 0;
bool capturedPreviousDisableRespawnTimes = false;

public Plugin myinfo = {
    name = "Low Population Respawn Control",
    author = "MegaLeg, MindfulProtons",
    description = "Disable respawn times during low population conditions",
    version = "1.0",
    url = "https://git.upwardmc.net/UpwardMC/TF2/LowPopNoAutokick"
};

public void OnPluginStart() {
    mpDisableRespawnTimesConVar = FindConVar("mp_disable_respawn_times");
    sourceTVConVar = FindConVar("tv_enable");
    lprcTriggerBelowConVar = CreateConVar("sm_disable_respawn_times_threshold", "10", "Player count required to enable respawn times", FCVAR_NONE, true, 2.0, true, MAXPLAYERS - 1.0);

    HookConVarChange(lprcTriggerBelowConVar, lprcTriggerBelowChanged);

    PrintToServer("[LowPopulationRespawnControl] Plugin loaded");
}

public void OnPluginEnd() {
    if (capturedPreviousDisableRespawnTimes) {
        SetConVarInt(mpDisableRespawnTimesConVar, originalDisableRespawnTimes);
    }
}

public void OnConfigsExecuted() {
    if (!capturedPreviousDisableRespawnTimes) {
        originalDisableRespawnTimes = GetConVarInt(mpDisableRespawnTimesConVar);

        capturedPreviousDisableRespawnTimes = true;
    }

    checkRespawnThreshold();
}

public void lprcTriggerBelowChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    checkRespawnThreshold();
}

public void OnClientPutInServer(int client) {
    checkRespawnThreshold();
}

public void OnClientDisconnect_Post(int client) {
    checkRespawnThreshold();
}

void checkRespawnThreshold() {
    // STV bot or TF bots could theoretically join before configs execute
    if (!capturedPreviousDisableRespawnTimes) {
        return;
    }

    int lprcTriggerBelowValue = GetConVarInt(lprcTriggerBelowConVar);
    int connectedClients = GetClientCount(false);

    int sourceTVActiveValue = GetConVarInt(sourceTVConVar);

    if (sourceTVActiveValue != 0) {
        connectedClients = connectedClients - 1;
    }

    bool shouldDisableRespawnTimes = connectedClients < lprcTriggerBelowValue;

    if (shouldDisableRespawnTimes) {
        SetConVarInt(mpDisableRespawnTimesConVar, 1);
        PrintToServer("Current playercount is below %i players! Instant respawn is on.", lprcTriggerBelowValue);
    } else {
        SetConVarInt(mpDisableRespawnTimesConVar, 0);
        // PrintToServer("Current playercount is at or above %i players! Instant respawn is off.", lprcTriggerBelowValue);
    }
}