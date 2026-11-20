#include <sourcemod>

#define PLUGIN_VERSION "1.4.1"

new bool:lateLoaded

public Plugin:myinfo =
{
	name = "Auto-Kick Protector",
	author = "Spartan_C001, MindfulProtons",
	description = "Protects players from being auto-kicked. Original modified for fixes.",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=224305"
}

public APLRes:AskPluginLoad2(Handle:myself,bool:late,String:error[],err_max)
{
	lateLoaded = late
	return APLRes_Success
}

public OnPluginStart()
{
	LoadTranslations("common.phrases")
	CreateConVar("sm_autokick_protector_version",PLUGIN_VERSION,"Auto-Kick Disabler Version",FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD)
	CreateConVar("sm_autokick_protector_flag","a","Admin flag to protect from autokick (Default 'a' - Reserved Slot).")
	CreateConVar("sm_autokick_protector_manual_flag","b","Admin flag to use command (Default 'b' - Generic Admin).")
	RegConsoleCmd("sm_autokick_protector_manual",CMD_ManualProtect,"Command to manually protect a player.")
	AutoExecConfig(true,"plugin.autokickprotector")
	if(lateLoaded)
	{
		for(new i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i) && !IsFakeClient(i))
			{
				OnClientPostAdminCheck(i)
			}
		}
	}
}

public OnClientPostAdminCheck(client)
{
	if(!IsClientInGame(client) || IsFakeClient(client))
		return;

	new AdminFlag:conVarFlag;
	new String:conVarFlagBuffer[2];
	GetConVarString(FindConVar("sm_autokick_protector_flag"),conVarFlagBuffer,sizeof(conVarFlagBuffer));

	if(!FindFlagByChar(conVarFlagBuffer[0],conVarFlag))
	{
		PrintToServer("[SM] Warning: Invalid flag supplied in 'sm_autokick_protector_flag'. Using default (a).");
		BitToFlag(ADMFLAG_RESERVATION,conVarFlag);
	}

	new flags = GetUserFlagBits(client);

	if((flags & ADMFLAG_ROOT) || (flags & FlagToBit(conVarFlag)))
	{
		ServerCommand("mp_disable_autokick %d",GetClientUserId(client));
		ServerExecute();

		PrintToServer("[SM] Auto-kick protection enabled for %N.",client);
	}
}

public Action:CMD_ManualProtect(client,args)
{
	new AdminFlag:conVarFlag
	new String:conVarFlagBuffer[2]
	GetConVarString(FindConVar("sm_autokick_protector_manual_flag"),conVarFlagBuffer,sizeof(conVarFlagBuffer))
	if(!FindFlagByChar(conVarFlagBuffer[0],conVarFlag))
	{
		ReplyToCommand(client,"[SM] Warning: Invalid flag supplied in 'sm_autokick_protector_manual_flag'. Using default (b).")
		BitToFlag(ADMFLAG_GENERIC,conVarFlag)
	}
	if(CheckCommandAccess(client,"",ADMFLAG_ROOT,true) || CheckCommandAccess(client,"",FlagToBit(conVarFlag),true))
	{
		if(args < 1 || args > 1)
		{
			ReplyToCommand(client,"[SM] Usage: sm_autokick_protector_manual <#userid|name>")
			return Plugin_Handled
		}
		new String:target[64]
		new targetClient = FindTarget(client,target)
		ServerCommand("mp_disable_autokick %d",GetClientUserId(targetClient))
		ReplyToCommand(client,"[SM] %N is now protected from afk auto-kick!",targetClient)
		return Plugin_Handled
	}
	else
	{
		ReplyToCommand(client,"[SM] You do not have access to this command!")
		return Plugin_Handled
	}
}