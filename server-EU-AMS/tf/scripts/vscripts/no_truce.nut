//Script by LizardOfOz
//Feel free to use

if (!IsHolidayActive(2) && !IsHolidayMap(2)) return;

::no_truce <- {
    gamerules = Entities.FindByClassname(null, "tf_gamerules"),
    OnGameEvent_recalculate_truce = function(params)
    {
        local isTruce = NetProps.GetPropBool(gamerules, "m_bTruceActive");
        NetProps.SetPropBool(gamerules, "m_bTruceActive", false);

        local text_tf = SpawnEntityFromTable("game_text_tf", {
            message = isTruce ? "No Truce! Keep on Killing!" : "Boss left the battle!",
            icon = "ico_notify_flag_moving_alt",
            background = 0,
            display_to_team = 0
        });
        NetProps.SetPropBool(text_tf, "m_bForcePurgeFixedupStrings", true);
        EntFireByHandle(text_tf, "Display", "", 0, null, null);
        EntFireByHandle(text_tf, "Kill", "", 1, null, null);
    }
};

EntFireByHandle(
    Entities.FindByClassname(null, "tf_gamerules"),
    "RunScriptCode",
    "::__CollectGameEventCallbacks(no_truce)",
    1, null, null);