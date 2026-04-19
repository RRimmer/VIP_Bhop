#pragma semicolon 1
#pragma newdecls required

#include <vip_core>
#include <sdktools>

int MessageCvar;
int NotifyCvar;
bool BhopAllowed[MAXPLAYERS + 1];
int AllowTime[MAXPLAYERS + 1];
int LockTime[MAXPLAYERS + 1];
ConVar mp_freezetime;
ConVar sv_enablebunnyhopping;
ConVar sv_autobunnyhopping;
Handle BhopStartTimer[MAXPLAYERS + 1];
Handle BhopAllowTimer[MAXPLAYERS + 1];
Handle BhopLockTimer[MAXPLAYERS + 1];
int AllowTimeCvar;
int LockTimeCvar;
Handle RoundStartNotifyTimer;
int RestrictTypeCvar;
int RestrictTimeCvar;
int FirstRoundOffCvar;
bool g_HasAccess[MAXPLAYERS + 1];
float g_LastAccessCheck[MAXPLAYERS + 1];
const float ACCESS_CACHE_TTL = 0.5;
bool g_DamageRestricted[MAXPLAYERS + 1];
Handle BhopRestrictTimer[MAXPLAYERS + 1];
ConVar g_hAuditIntervalCvar;
ConVar g_hAuditForceCvar;
float g_fAuditInterval;
int g_iAuditForce;
Handle g_hAuditTimer;
int g_iAuditSeq[MAXPLAYERS + 1];

enum BhopNoticeType
{
	Notice_Wait = 0,
	Notice_Ready,
	Notice_Off,
	Notice_FirstRound,
	Notice_Count
};

static float g_LastNoticeTime[view_as<int>(Notice_Count)];
static bool g_FirstActivationDone = false;

static const char Feature[] = "bhop";

public Plugin myinfo = 
{
	name = "[VIP] BHOP | AI", 
	author = "Rimmer & Claude Haiku 4.5", 
	version = "2.1", 
	url = "github.com/RRimmer"
};

public void OnPluginStart()
{
	ConVar Cvar;
	Cvar = CreateConVar("bhop_info", "2", "Режим оповещений (0 выкл, 1 чат, 2 сверху)");
	Cvar.AddChangeHook(ConVarChangeCallbackBhopInfo);
	MessageCvar = Cvar.IntValue;
	
	Cvar = CreateConVar("bhop_notify", "0", "Кому писать сообщения (0 - всем, 1 - только VIP с доступом)", _, true, 0.0, true, 1.0);
	NotifyCvar = Cvar.IntValue;
	Cvar.AddChangeHook(ConVarChangeCallbackNotify);
	
	Cvar = CreateConVar("bhop_allowtime", "5", "Сколько секунд будет доступен BHOP (0 - всегда доступен на протижении раунда)", _, true, 0.0);
	AllowTimeCvar = Cvar.IntValue;
	Cvar.AddChangeHook(ConVarChangeCallbackAllowTime);
	
	Cvar = CreateConVar("bhop_locktime", "15", "Через сколько будет доступен/перезаряжаться BHOP (0 - сразу доступен/отключить)", _, true, 0.0);
	LockTimeCvar = Cvar.IntValue;
	Cvar.AddChangeHook(ConVarChangeCallbackLockTime);

	Cvar = CreateConVar("bhop_restrict_type", "0", "Отключать BHOP после урона от противника (0 - выкл, 1 - вкл)", _, true, 0.0, true, 1.0);
	RestrictTypeCvar = Cvar.IntValue;
	Cvar.AddChangeHook(ConVarChangeCallbackRestrictType);

	Cvar = CreateConVar("bhop_restrict_time", "2", "Сколько секунд BHOP отключен после урона от противника", _, true, 0.0);
	RestrictTimeCvar = Cvar.IntValue;
	Cvar.AddChangeHook(ConVarChangeCallbackRestrictTime);

	Cvar = CreateConVar("bhop_first_round_off", "0", "Отключать BHOP в первом раунде (с поддержкой mp_halftime) (0 - выкл, 1 - вкл)", _, true, 0.0, true, 1.0);
	FirstRoundOffCvar = Cvar.IntValue;
	Cvar.AddChangeHook(ConVarChangeCallbackFirstRoundOff);

	g_hAuditIntervalCvar = CreateConVar("bhop_stability_audit_interval", "0.25", "Интервал аудита клиентских sv_enable/sv_auto (0 - выкл)", _, true, 0.0, true, 10.0);
	g_fAuditInterval = g_hAuditIntervalCvar.FloatValue;
	g_hAuditIntervalCvar.AddChangeHook(ConVarChangeCallbackAuditInterval);

	g_hAuditForceCvar = CreateConVar("bhop_stability_audit_force", "1", "Принудительно восстанавливать BHOP при mismatch клиентских cvar (0/1)", _, true, 0.0, true, 1.0);
	g_iAuditForce = g_hAuditForceCvar.IntValue;
	g_hAuditForceCvar.AddChangeHook(ConVarChangeCallbackAuditForce);
	
	if (VIP_IsVIPLoaded())
		VIP_OnVIPLoaded();
	
	mp_freezetime = FindConVar("mp_freezetime");
	sv_enablebunnyhopping = FindConVar("sv_enablebunnyhopping");
	sv_autobunnyhopping = FindConVar("sv_autobunnyhopping");
	
	HookEvent("round_start", eRoundStart, EventHookMode_PostNoCopy);
	HookEvent("player_hurt", ePlayerHurt, EventHookMode_Post);
	
	LoadTranslations("vip_bhop.phrases");
	AutoExecConfig(true, "VIP_Bhop", "vip");
	StartAuditTimer();
}

public void OnPluginEnd()
{
	delete g_hAuditTimer;
	g_hAuditTimer = null;

	if (CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "VIP_UnregisterFeature") == FeatureStatus_Available)
	{
		VIP_UnregisterFeature(Feature);
	}
}

public void OnMapEnd()
{
	RoundStartNotifyTimer = null;
	delete g_hAuditTimer;
	g_hAuditTimer = null;
	for (int i = 1; i <= MaxClients; i++)
	{
		BhopStartTimer[i] = null;
		BhopAllowTimer[i] = null;
		BhopLockTimer[i] = null;
		BhopAllowed[i] = false;
		AllowTime[i] = 0;
		LockTime[i] = 0;
		g_DamageRestricted[i] = false;
		BhopRestrictTimer[i] = null;
		g_HasAccess[i] = false;
		g_LastAccessCheck[i] = 0.0;
		g_iAuditSeq[i] = 0;
	}
}

public void OnClientDisconnect(int client)
{
	ResetBhopForClient(client);
	g_HasAccess[client] = false;
	g_LastAccessCheck[client] = 0.0;
	g_iAuditSeq[client] = 0;
}

public void OnMapStart()
{
	StartAuditTimer();
}

void ConVarChangeCallbackBhopInfo(ConVar cvar, const char[] oldvalue, const char[] newvalue)
{
	MessageCvar = cvar.IntValue;
}

void ConVarChangeCallbackNotify(ConVar cvar, const char[] oldvalue, const char[] newvalue)
{
	NotifyCvar = cvar.IntValue;
}

void ConVarChangeCallbackAllowTime(ConVar cvar, const char[] oldvalue, const char[] newvalue)
{
	AllowTimeCvar = cvar.IntValue;
}

void ConVarChangeCallbackLockTime(ConVar cvar, const char[] oldvalue, const char[] newvalue)
{
	LockTimeCvar = cvar.IntValue;
}

void ConVarChangeCallbackRestrictType(ConVar cvar, const char[] oldvalue, const char[] newvalue)
{
	RestrictTypeCvar = cvar.IntValue;

	if (RestrictTypeCvar != 0)
		return;

	for (int i = 1; i <= MaxClients; i++)
	{
		delete BhopRestrictTimer[i];

		if (!g_DamageRestricted[i])
			continue;

		g_DamageRestricted[i] = false;
		if (IsClientInGame(i) && !IsFakeClient(i))
			AutoBhop(i, BhopAllowed[i] && (AllowTimeCvar == 0 || AllowTime[i] > 0));
	}
}

void ConVarChangeCallbackRestrictTime(ConVar cvar, const char[] oldvalue, const char[] newvalue)
{
	RestrictTimeCvar = cvar.IntValue;
}

void ConVarChangeCallbackFirstRoundOff(ConVar cvar, const char[] oldvalue, const char[] newvalue)
{
	FirstRoundOffCvar = cvar.IntValue;
}

void ConVarChangeCallbackAuditInterval(ConVar cvar, const char[] oldvalue, const char[] newvalue)
{
	g_fAuditInterval = cvar.FloatValue;
	StartAuditTimer();
}

void ConVarChangeCallbackAuditForce(ConVar cvar, const char[] oldvalue, const char[] newvalue)
{
	g_iAuditForce = cvar.IntValue;
}

bool HasBhopAccess(int client)
{
	return IsClientInGame(client)
		&& !IsFakeClient(client)
		&& VIP_IsClientVIP(client)
		&& VIP_IsClientFeatureUse(client, Feature);
}

bool HasBhopAccessCached(int client, bool force = false)
{
	if (!IsClientInGame(client) || IsFakeClient(client))
	{
		g_HasAccess[client] = false;
		g_LastAccessCheck[client] = 0.0;
		return false;
	}

	float now = GetGameTime();
	if (!force && g_LastAccessCheck[client] > 0.0 && now - g_LastAccessCheck[client] < ACCESS_CACHE_TTL)
		return g_HasAccess[client];

	g_LastAccessCheck[client] = now;
	g_HasAccess[client] = VIP_IsClientVIP(client) && VIP_IsClientFeatureUse(client, Feature);
	return g_HasAccess[client];
}

bool HasTrackedState(int client)
{
	return BhopAllowed[client]
		|| AllowTime[client] > 0
		|| LockTime[client] > 0
		|| BhopStartTimer[client] != null
		|| BhopAllowTimer[client] != null
		|| BhopLockTimer[client] != null
		|| BhopRestrictTimer[client] != null;
}

void StartAuditTimer()
{
	delete g_hAuditTimer;
	g_hAuditTimer = null;

	if (g_fAuditInterval <= 0.0)
		return;

	g_hAuditTimer = CreateTimer(g_fAuditInterval, Timer_AuditClientReplicas, 0, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

int PackAuditQueryData(int client, int expected, int seq)
{
	return client | (expected << 7) | ((seq & 0xFF) << 8);
}

Action Timer_AuditClientReplicas(Handle timer, any data)
{
	if (g_fAuditInterval <= 0.0)
	{
		g_hAuditTimer = null;
		return Plugin_Stop;
	}

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || IsFakeClient(client))
			continue;

		if (!HasTrackedState(client))
			continue;

		int expected = IsBhopActiveNow(client) ? 1 : 0;
		g_iAuditSeq[client]++;
		int packed = PackAuditQueryData(client, expected, g_iAuditSeq[client]);

		QueryClientConVar(client, "sv_enablebunnyhopping", OnClientCvarAudit, packed);
		QueryClientConVar(client, "sv_autobunnyhopping", OnClientCvarAudit, packed);
	}

	return Plugin_Continue;
}

public void OnClientCvarAudit(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, any value)
{
	if (!client || !IsClientInGame(client) || IsFakeClient(client))
		return;

	if (result != ConVarQuery_Okay)
		return;

	int packed = value;
	int packedClient = packed & 0x7F;
	int expectedAtQuery = (packed >> 7) & 1;
	int seq = (packed >> 8) & 0xFF;

	if (packedClient != client)
		return;

	if ((g_iAuditSeq[client] & 0xFF) != seq)
		return;

	int expectedNow = IsBhopActiveNow(client) ? 1 : 0;
	if (expectedAtQuery != expectedNow)
		return;

	int actual = StringToInt(cvarValue);
	if (actual == expectedNow)
		return;

	if (g_iAuditForce != 0)
		AutoBhop(client, expectedNow != 0);
}

bool IsBhopTimeActive(int client)
{
	return BhopAllowed[client] && (AllowTimeCvar == 0 || AllowTime[client] > 0);
}

int GetClientLockTime(int client)
{
	float lockFloat = VIP_GetClientFeatureFloat(client, Feature);

	// 1 or 1.0 means feature enabled with global lock value.
	if (lockFloat >= 0.999 && lockFloat <= 1.001)
		return LockTimeCvar;

	// Custom value uses integer part: 1.1 -> 1, 5.2 -> 5.
	int lockTime = RoundToFloor(lockFloat);
	if (lockTime < 0)
		lockTime = 0;

	return lockTime;
}

int GetRoundInCurrentHalf()
{
	static ConVar mp_maxrounds = null;
	static ConVar mp_halftime = null;

	if (mp_maxrounds == null)
		mp_maxrounds = FindConVar("mp_maxrounds");

	if (mp_halftime == null)
		mp_halftime = FindConVar("mp_halftime");

	int totalRoundsPlayed = GameRules_GetProp("m_totalRoundsPlayed");
	bool halftimeEnabled = (mp_halftime != null && mp_halftime.BoolValue);

	if (!halftimeEnabled || mp_maxrounds == null)
		return totalRoundsPlayed + 1;

	int roundsPerHalf = mp_maxrounds.IntValue / 2;
	if (roundsPerHalf <= 0)
		return totalRoundsPlayed + 1;

	return (totalRoundsPlayed % roundsPerHalf) + 1;
}

bool IsFirstRoundBhopDisabled()
{
	if (FirstRoundOffCvar == 0)
		return false;

	if (GameRules_GetProp("m_bWarmupPeriod") == 1)
		return false;

	return GetRoundInCurrentHalf() == 1;
}

bool IsBhopActiveNow(int client)
{
	return IsBhopTimeActive(client) && !g_DamageRestricted[client];
}

void ApplyDamageRestrict(int client)
{
	if (RestrictTypeCvar == 0 || RestrictTimeCvar <= 0)
		return;

	g_DamageRestricted[client] = true;
	delete BhopRestrictTimer[client];
	BhopRestrictTimer[client] = CreateTimer(float(RestrictTimeCvar), Timer_RestrictEnd, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	AutoBhop(client, false);
	NotifyRestrictClient(client, "bhop_restricttime_chat", "bhop_restricttime", true, RestrictTimeCvar);
}

void ResetBhopForClient(int client)
{
	BhopAllowed[client] = false;
	AllowTime[client] = 0;
	LockTime[client] = 0;
	delete BhopStartTimer[client];
	delete BhopAllowTimer[client];
	delete BhopLockTimer[client];
	delete BhopRestrictTimer[client];
	g_DamageRestricted[client] = false;

	if (IsClientInGame(client) && !IsFakeClient(client))
		AutoBhop(client, false);
}

bool ShouldReceiveNotice(int client)
{
	if (!IsClientInGame(client) || IsFakeClient(client))
		return false;

	if (NotifyCvar == 0)
		return true;

	if (GetClientTeam(client) <= 1)
		return false;

	return HasBhopAccessCached(client);
}

bool ShouldBroadcast(BhopNoticeType type)
{
	float now = GetGameTime();
	if (now - g_LastNoticeTime[type] < 0.1)
		return false;

	g_LastNoticeTime[type] = now;
	return true;
}

void BroadcastNotice(const char[] phraseChat, const char[] phraseHUD, int value = 0)
{
	if (MessageCvar == 0)
		return;

	if (MessageCvar == 1)
	{
		if (NotifyCvar == 0)
		{
			VIP_PrintToChatAll("%t", phraseChat, value);
			return;
		}

		for (int i = 1; i <= MaxClients; i++)
		{
			if (ShouldReceiveNotice(i))
				VIP_PrintToChatClient(i, "%t", phraseChat, value);
		}
	}
	else if (MessageCvar == 2)
	{
		char hudBuffer[256];
		FormatEx(hudBuffer, sizeof(hudBuffer), "%t", phraseHUD, value);
		Event newevent = CreateEvent("show_survival_respawn_status", true);
		if (newevent != null)
		{
			newevent.SetString("loc_token", hudBuffer);
			newevent.SetInt("duration", 5);
			newevent.SetInt("userid", -1);

			for (int i = 1; i <= MaxClients; i++)
			{
				if (ShouldReceiveNotice(i))
					newevent.FireToClient(i);
			}
			newevent.Cancel();
		}
		else
		{
			for (int i = 1; i <= MaxClients; i++)
			{
				if (ShouldReceiveNotice(i))
					PrintHintText(i, "%s", hudBuffer);
			}
		}
	}
}

void NotifyRestrictClient(int client, const char[] phraseChat, const char[] phraseHUD, bool withValue = false, int value = 0)
{
	if (MessageCvar == 0 || !IsClientInGame(client) || IsFakeClient(client))
		return;

	if (MessageCvar == 1)
	{
		if (withValue)
			VIP_PrintToChatClient(client, "%t", phraseChat, value);
		else
			VIP_PrintToChatClient(client, "%t", phraseChat);
	}
	else if (MessageCvar == 2)
	{
		char hudBuffer[256];
		if (withValue)
			FormatEx(hudBuffer, sizeof(hudBuffer), "%t", phraseHUD, value);
		else
			FormatEx(hudBuffer, sizeof(hudBuffer), "%t", phraseHUD);

		Event newevent = CreateEvent("show_survival_respawn_status", true);
		if (newevent != null)
		{
			newevent.SetString("loc_token", hudBuffer);
			newevent.SetInt("duration", 5);
			newevent.SetInt("userid", GetClientUserId(client));
			newevent.FireToClient(client);
			newevent.Cancel();
		}
		else
		{
			PrintHintText(client, "%s", hudBuffer);
		}
	}
}

void AutoBhop(int client, bool bEnable)
{
	if (bEnable)
	{
		sv_enablebunnyhopping.ReplicateToClient(client, "1");
		sv_autobunnyhopping.ReplicateToClient(client, "1");
	}
	else
	{
		sv_enablebunnyhopping.ReplicateToClient(client, "0");
		sv_autobunnyhopping.ReplicateToClient(client, "0");
	}
}

public void VIP_OnVIPLoaded()
{
	VIP_RegisterFeature(Feature, FLOAT);
}

void ePlayerHurt(Event event, const char[] eventname, bool dontbroadcast)
{
	if (RestrictTypeCvar == 0 || RestrictTimeCvar <= 0)
		return;

	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));

	if (!victim || !attacker || victim == attacker)
		return;

	if (!IsClientInGame(victim) || IsFakeClient(victim) || !IsClientInGame(attacker))
		return;

	if (GetClientTeam(victim) < 2 || GetClientTeam(attacker) < 2 || GetClientTeam(victim) == GetClientTeam(attacker))
		return;

	if (!IsBhopTimeActive(victim) || !HasBhopAccessCached(victim))
		return;

	ApplyDamageRestrict(victim);
}

void eRoundStart(Event event, const char[] eventname, bool dontbroadcast)
{
	g_FirstActivationDone = false;
	for (int i = 0; i < view_as<int>(Notice_Count); i++)
		g_LastNoticeTime[i] = -9999.0;

	if (RoundStartNotifyTimer != null)
	{
		delete RoundStartNotifyTimer;
		RoundStartNotifyTimer = null;
	}

	float freezeTime = mp_freezetime.FloatValue;
	bool blockForFirstRound = IsFirstRoundBhopDisabled();

	if (!blockForFirstRound && LockTimeCvar > 0)
		RoundStartNotifyTimer = CreateTimer(freezeTime, Timer_RoundStartNotify, 0, TIMER_FLAG_NO_MAPCHANGE);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		ResetBhopForClient(i);

		if (!HasBhopAccess(i))
			continue;

		if (blockForFirstRound)
			continue;

		if (IsPlayerAlive(i))
		{
			int clientLockTime = GetClientLockTime(i);
			float startDelay = freezeTime + (clientLockTime > 0 ? float(clientLockTime) : 0.0);
			BhopStartTimer[i] = CreateTimer(startDelay, Timer_BhopStart, GetClientUserId(i), TIMER_FLAG_NO_MAPCHANGE);
		}
	}

	if (blockForFirstRound && ShouldBroadcast(Notice_FirstRound))
		BroadcastNotice("bhop_first_round_off_chat", "bhop_first_round_off");
}

Action Timer_RoundStartNotify(Handle timer, any data)
{
	RoundStartNotifyTimer = null;

	if (LockTimeCvar > 0 && ShouldBroadcast(Notice_Wait))
		BroadcastNotice("bhop_time_waitchat", "bhop_time_wait", LockTimeCvar);

	return Plugin_Stop;
}

Action Timer_BhopStart(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if (!client)
		return Plugin_Stop;

	BhopStartTimer[client] = null;

	if (!HasBhopAccess(client))
	{
		ResetBhopForClient(client);
		return Plugin_Stop;
	}

	BhopAllowed[client] = true;
	AutoBhop(client, IsBhopActiveNow(client));

	if (AllowTimeCvar > 0)
	{
		AllowTime[client] = AllowTimeCvar;
		BhopAllowTimer[client] = CreateTimer(1.0, Timer_AllowTick, GetClientUserId(client), TIMER_REPEAT);

		char chatPhrase[32];
		char hudPhrase[32];
		if (g_FirstActivationDone)
		{
			strcopy(chatPhrase, sizeof(chatPhrase), "bhop_time_readychat");
			strcopy(hudPhrase, sizeof(hudPhrase), "bhop_time_ready");
		}
		else
		{
			strcopy(chatPhrase, sizeof(chatPhrase), "bhop_time_onchat_first");
			strcopy(hudPhrase, sizeof(hudPhrase), "bhop_time_on_first");
		}
		if (ShouldBroadcast(Notice_Ready))
			BroadcastNotice(chatPhrase, hudPhrase, AllowTimeCvar);
	}
	else
	{
		AllowTime[client] = 999999;
		if (ShouldBroadcast(Notice_Ready))
			BroadcastNotice("bhop_time_infinitechat", "bhop_time_infinite");
	}

	g_FirstActivationDone = true;
	
	return Plugin_Stop;
}

Action Timer_AllowTick(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if (!client || !IsClientInGame(client))
	{
		BhopAllowTimer[client] = null;
		return Plugin_Stop;
	}

	if (!HasBhopAccess(client))
	{
		ResetBhopForClient(client);
		return Plugin_Stop;
	}
	
	AllowTime[client]--;
	if (AllowTime[client] < 1)
	{
		BhopAllowTimer[client] = null;
		int clientLockTime = GetClientLockTime(client);
		
		if (clientLockTime == 0)
		{
			BhopAllowed[client] = true;
			AutoBhop(client, IsBhopActiveNow(client));
			
			if (AllowTimeCvar > 0)
			{
				AllowTime[client] = AllowTimeCvar;
				BhopAllowTimer[client] = CreateTimer(1.0, Timer_AllowTick, GetClientUserId(client), TIMER_REPEAT);
				if (ShouldBroadcast(Notice_Ready))
					BroadcastNotice("bhop_time_readychat", "bhop_time_ready", AllowTimeCvar);
			}
			else
			{
				AllowTime[client] = 999999;
				if (ShouldBroadcast(Notice_Ready))
					BroadcastNotice("bhop_time_infinitechat", "bhop_time_infinite");
			}
		}
		else
		{
			LockTime[client] = clientLockTime;
			AutoBhop(client, false);
			BhopLockTimer[client] = CreateTimer(1.0, Timer_LockTick, GetClientUserId(client), TIMER_REPEAT);
			if (ShouldBroadcast(Notice_Off))
				BroadcastNotice("bhop_time_offchat", "bhop_time_off", clientLockTime);
		}
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

Action Timer_LockTick(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if (!client || !IsClientInGame(client))
	{
		BhopLockTimer[client] = null;
		return Plugin_Stop;
	}

	if (!HasBhopAccess(client))
	{
		ResetBhopForClient(client);
		return Plugin_Stop;
	}
	
	LockTime[client]--;
	if (LockTime[client] < 1)
	{
		BhopLockTimer[client] = null;
		
		BhopAllowed[client] = true;
		AutoBhop(client, IsBhopActiveNow(client));
		
		if (AllowTimeCvar > 0)
		{
			AllowTime[client] = AllowTimeCvar;
			BhopAllowTimer[client] = CreateTimer(1.0, Timer_AllowTick, GetClientUserId(client), TIMER_REPEAT);
			if (ShouldBroadcast(Notice_Ready))
				BroadcastNotice("bhop_time_readychat", "bhop_time_ready", AllowTimeCvar);
		}
		else
		{
			AllowTime[client] = 999999;
			if (ShouldBroadcast(Notice_Ready))
				BroadcastNotice("bhop_time_infinitechat", "bhop_time_infinite");
		}
		
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

Action Timer_RestrictEnd(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if (!client)
		return Plugin_Stop;

	BhopRestrictTimer[client] = null;
	g_DamageRestricted[client] = false;

	if (!IsClientInGame(client) || IsFakeClient(client))
		return Plugin_Stop;

	if (!HasBhopAccessCached(client, true))
	{
		ResetBhopForClient(client);
		return Plugin_Stop;
	}

	bool canEnable = IsBhopTimeActive(client);
	AutoBhop(client, canEnable);

	if (canEnable)
		NotifyRestrictClient(client, "bhop_restricton_chat", "bhop_restricton");

	return Plugin_Stop;
}

public Action OnPlayerRunCmd(int client, int & buttons, int & impulse, float vel[3], float angles[3], int & weapon, int & subtype, int & cmdnum, int & tickcount, int & seed, int mouse[2])
{
	if (!IsClientInGame(client) || IsFakeClient(client))
		return Plugin_Continue;

	bool onGround = (GetEntityFlags(client) & FL_ONGROUND) != 0;

	bool hasState = HasTrackedState(client);

	if (!hasState)
		return Plugin_Continue;

	if (!HasBhopAccessCached(client))
	{
		ResetBhopForClient(client);
		return Plugin_Continue;
	}

	if (IsPlayerAlive(client) && (buttons & IN_JUMP) && IsBhopActiveNow(client))
	{
		MoveType moveType = GetEntityMoveType(client);
		if (moveType != MOVETYPE_LADDER && GetEntProp(client, Prop_Data, "m_nWaterLevel") <= 1)
		{
			SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);

			if (!onGround)
				buttons &= ~IN_JUMP;
		}
	}
	
	return Plugin_Continue;
}
