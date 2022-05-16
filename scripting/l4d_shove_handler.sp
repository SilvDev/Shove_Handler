/*
*	Shove Handler
*	Copyright (C) 2022 Silvers
*
*	This program is free software: you can redistribute it and/or modify
*	it under the terms of the GNU General Public License as published by
*	the Free Software Foundation, either version 3 of the License, or
*	(at your option) any later version.
*
*	This program is distributed in the hope that it will be useful,
*	but WITHOUT ANY WARRANTY; without even the implied warranty of
*	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*	GNU General Public License for more details.
*
*	You should have received a copy of the GNU General Public License
*	along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/



#define PLUGIN_VERSION		"1.0"

/*=======================================================================================
	Plugin Info:

*	Name	:	[L4D & L4D2] Shove Handler
*	Author	:	SilverShot
*	Descrp	:	Overrides the shoving system, allowing to set number of shoves before killing, stumble and damage per bash, for SI and Common.
*	Link	:	https://forums.alliedmods.net/showthread.php?t=337808
*	Plugins	:	https://sourcemod.net/plugins.php?exact=exact&sortby=title&search=1&author=Silvers

========================================================================================
	Change Log:

1.0 (16-May-2022)
	- Initial release.

======================================================================================*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <left4dhooks>

#define CVAR_FLAGS			FCVAR_NOTIFY
#define GAMEDATA			"l4d_shove_handler"

ConVar g_hCvarAllow, g_hCvarMPGameMode, g_hCvarModes, g_hCvarModesOff, g_hCvarModesTog, g_hCvarBack, g_hCvarStumble, g_hCvarTypes, g_hCvarCount[9], g_hCvarDamage[9], g_hCvarType[9];
bool g_bCvarAllow, g_bLeft4Dead2, g_bCvarBack;
float g_fCvarDamage[9];
int g_iCvarStumble, g_iCvarTypes, g_iCvarCount[9], g_iCvarDamage[9];
int g_iMaxTypes, g_iShoves[2048][4]; // [0] = Entity reference. [1] = Shove count. [2] = Health. [3] = Type
float g_fShove[2048];

enum
{
	TYPE_COMMON		= 0,
	TYPE_SMOKER		= 1,
	TYPE_BOOMER		= 2,
	TYPE_HUNTER		= 4,
	TYPE_SPITTER	= 8,
	TYPE_JOCKEY		= 16,
	TYPE_CHARGER	= 32,
	TYPE_TANK		= 64,
	TYPE_WITCH		= 128,
}

enum
{
	INDEX_COMMON	= 0,
	INDEX_SMOKER	= 1,
	INDEX_BOOMER	= 2,
	INDEX_HUNTER	= 3,
	INDEX_SPITTER	= 4,
	INDEX_JOCKEY	= 5,
	INDEX_CHARGER	= 6,
	INDEX_TANK		= 7,
	INDEX_WITCH		= 8,
}

enum
{
	INDEX_ENTITY	= 0,
	INDEX_COUNT		= 1,
	INDEX_HEALTH	= 2,
	INDEX_TYPE		= 3
}

static const char g_sSounds[6][] =
{
	"player/survivor/hit/rifle_swing_hit_infected7.wav",
	"player/survivor/hit/rifle_swing_hit_infected8.wav",
	"player/survivor/hit/rifle_swing_hit_infected9.wav",
	"player/survivor/hit/rifle_swing_hit_infected10.wav",
	"player/survivor/hit/rifle_swing_hit_infected11.wav",
	"player/survivor/hit/rifle_swing_hit_infected12.wav"
};

static const char g_sClowns[6][] =
{
	"player/survivor/hit/rifle_swing_hit_clown.wav",
	"player/survivor/hit/rifle_swing_hit_clown2.wav",
	"player/survivor/hit/rifle_swing_hit_clown3.wav",
	"player/survivor/hit/rifle_swing_hit_clown4.wav",
	"player/survivor/hit/rifle_swing_hit_clown5.wav",
	"player/survivor/hit/rifle_swing_hit_clown6.wav"
};



// ====================================================================================================
//					PLUGIN INFO / START / END
// ====================================================================================================
public Plugin myinfo =
{
	name = "[L4D & L4D2] Shove Handler",
	author = "SilverShot",
	description = "Overrides the shoving system, allowing to set number of shoves before killing, stumble and damage per bash, for SI and Common.",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=337808"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion test = GetEngineVersion();
	if( test == Engine_Left4Dead ) g_bLeft4Dead2 = false;
	else if( test == Engine_Left4Dead2 ) g_bLeft4Dead2 = true;
	else
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 1 & 2.");
		return APLRes_SilentFailure;
	}
	return APLRes_Success;
}

public void OnPluginStart()
{
	if( g_bLeft4Dead2 )		g_iMaxTypes = 9;
	else					g_iMaxTypes = 6;

	// ====================================================================================================
	// DETOURS
	// ====================================================================================================
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "gamedata/%s.txt", GAMEDATA);
	if( FileExists(sPath) == false ) SetFailState("\n==========\nMissing required file: \"%s\".\nRead installation instructions again.\n==========", sPath);

	Handle hGameData = LoadGameConfigFile(GAMEDATA);
	if( hGameData == null ) SetFailState("Failed to load \"%s.txt\" gamedata.", GAMEDATA);

	// Patch 1
	Handle hDetour = DHookCreateFromConf(hGameData, "CTerrorWeapon::OnSwingEnd");

	// Currently crashes when ignored
	if( !hDetour )
		SetFailState("Failed to find \"CCarProp::CTerrorWeapon::OnSwingEnd\" signature.");

	if( !DHookEnableDetour(hDetour, false, OnSwingEnd) )
		SetFailState("Failed to detour \"CCarProp::CTerrorWeapon::OnSwingEnd\".");

	// Patch 2
	hDetour = DHookCreateFromConf(hGameData, "Infected::OnAmbushed");

	if( !hDetour )
		SetFailState("Failed to find \"CCarProp::Infected::OnAmbushed\" signature.");

	if( !DHookEnableDetour(hDetour, false, OnAmbushed) )
		SetFailState("Failed to detour \"CCarProp::Infected::OnAmbushed\".");

	delete hGameData;
	delete hDetour;



	// ====================================================================================================
	// CVARS
	// ====================================================================================================
	g_hCvarAllow = CreateConVar(		"l4d_shove_handler_allow",				"1",			"0=Plugin off, 1=Plugin on.", CVAR_FLAGS );
	g_hCvarModes = CreateConVar(		"l4d_shove_handler_modes",				"",				"Turn on the plugin in these game modes, separate by commas (no spaces). (Empty = all).", CVAR_FLAGS );
	g_hCvarModesOff = CreateConVar(		"l4d_shove_handler_modes_off",			"",				"Turn off the plugin in these game modes, separate by commas (no spaces). (Empty = none).", CVAR_FLAGS );
	g_hCvarModesTog = CreateConVar(		"l4d_shove_handler_modes_tog",			"0",			"Turn on the plugin in these game modes. 0=All, 1=Coop, 2=Survival, 4=Versus, 8=Scavenge. Add numbers together.", CVAR_FLAGS );
	g_hCvarBack = CreateConVar(			"l4d_shove_handler_common_back",		"0",			"0=Off. 1=Allow (game default). Can Common Infected be insta-killed when first shoving their back.", CVAR_FLAGS );

	// Counts
	g_hCvarCount[0] = CreateConVar(		"l4d_shove_handler_count_common",		"0",			"0=Ignore shove count killing common. How many shoves does it take to kill a common infected (game default is 4).", CVAR_FLAGS );
	g_hCvarCount[1] = CreateConVar(		"l4d_shove_handler_count_smoker",		"0",			"0=Ignore shove count (unlimited shoves). How many shoves does it take to kill.", CVAR_FLAGS );
	g_hCvarCount[2] = CreateConVar(		"l4d_shove_handler_count_boomer",		"0",			"0=Ignore shove count (unlimited shoves). How many shoves does it take to kill.", CVAR_FLAGS );
	g_hCvarCount[3] = CreateConVar(		"l4d_shove_handler_count_hunter",		"0",			"0=Ignore shove count (unlimited shoves). How many shoves does it take to kill.", CVAR_FLAGS );
	if( g_bLeft4Dead2 )
	{
	g_hCvarCount[4] = CreateConVar(		"l4d_shove_handler_count_spitter",		"0",			"0=Ignore shove count (unlimited shoves). How many shoves does it take to kill.", CVAR_FLAGS );
	g_hCvarCount[5] = CreateConVar(		"l4d_shove_handler_count_jockey",		"0",			"0=Ignore shove count (unlimited shoves). How many shoves does it take to kill.", CVAR_FLAGS );
	g_hCvarCount[6] = CreateConVar(		"l4d_shove_handler_count_charger",		"0",			"0=Ignore shove count (unlimited shoves). How many shoves does it take to kill.", CVAR_FLAGS );
	}
	g_hCvarCount[7] = CreateConVar(		"l4d_shove_handler_count_tank",			"0",			"0=Ignore shove count (unlimited shoves). How many shoves does it take to kill.", CVAR_FLAGS );
	g_hCvarCount[8] = CreateConVar(		"l4d_shove_handler_count_witch",		"0",			"0=Ignore shove count (unlimited shoves). How many shoves does it take to kill.", CVAR_FLAGS );

	// Types
	g_hCvarTypes = CreateConVar(		"l4d_shove_handler_damaged",			"511",			"Who can be damaged when shoved: 0=None, 1=Common, 2=Smoker, 4=Boomer, 8=Hunter, 16=Spitter, 32=Jockey, 64=Charger, 128=Tank, 256=Witch. 511=All. Add numbers together.", CVAR_FLAGS );

	// Damage
	g_hCvarDamage[0] = CreateConVar(	"l4d_shove_handler_damage_common",		"10.0",			"0.0=None (game default). Amount of damage each shove causes. If using percentage type, 100.0 = full health.", CVAR_FLAGS );
	g_hCvarDamage[1] = CreateConVar(	"l4d_shove_handler_damage_smoker",		"10.0",			"0.0=None (game default). Amount of damage each shove causes. If using percentage type, 100.0 = full health.", CVAR_FLAGS );
	g_hCvarDamage[2] = CreateConVar(	"l4d_shove_handler_damage_boomer",		"10.0",			"0.0=None (game default). Amount of damage each shove causes. If using percentage type, 100.0 = full health.", CVAR_FLAGS );
	g_hCvarDamage[3] = CreateConVar(	"l4d_shove_handler_damage_hunter",		"10.0",			"0.0=None (game default). Amount of damage each shove causes. If using percentage type, 100.0 = full health.", CVAR_FLAGS );
	if( g_bLeft4Dead2 )
	{
	g_hCvarDamage[4] = CreateConVar(	"l4d_shove_handler_damage_spitter",		"10.0",			"0.0=None (game default). Amount of damage each shove causes. If using percentage type, 100.0 = full health.", CVAR_FLAGS );
	g_hCvarDamage[5] = CreateConVar(	"l4d_shove_handler_damage_jockey",		"10.0",			"0.0=None (game default). Amount of damage each shove causes. If using percentage type, 100.0 = full health.", CVAR_FLAGS );
	g_hCvarDamage[6] = CreateConVar(	"l4d_shove_handler_damage_charger",		"10.0",			"0.0=None (game default). Amount of damage each shove causes. If using percentage type, 100.0 = full health.", CVAR_FLAGS );
	}
	g_hCvarDamage[7] = CreateConVar(	"l4d_shove_handler_damage_tank",		"10.0",			"0.0=None (game default). Amount of damage each shove causes. If using percentage type, 100.0 = full health.", CVAR_FLAGS );
	g_hCvarDamage[8] = CreateConVar(	"l4d_shove_handler_damage_witch",		"10.0",			"0.0=None (game default). Amount of damage each shove causes. If using percentage type, 100.0 = full health.", CVAR_FLAGS );

	// Stumble
	g_hCvarStumble = CreateConVar(		"l4d_shove_handler_stumble",			"127",			"Stumble when shoved: 0=None, 1=Common, 2=Smoker, 4=Boomer, 8=Hunter, 16=Spitter, 32=Jockey, 64=Charger, 128=Tank (default off), 256=Witch (default off). 511=All. Add numbers together.", CVAR_FLAGS );

	// Damage Type
	g_hCvarType[0] = CreateConVar(		"l4d_shove_handler_type_common",		"1",			"1=Deal the damage value specified. 2=Deal the specified damage value as a percentage of their maximum health.", CVAR_FLAGS );
	g_hCvarType[1] = CreateConVar(		"l4d_shove_handler_type_smoker",		"1",			"1=Deal the damage value specified. 2=Deal the specified damage value as a percentage of their maximum health.", CVAR_FLAGS );
	g_hCvarType[2] = CreateConVar(		"l4d_shove_handler_type_boomer",		"1",			"1=Deal the damage value specified. 2=Deal the specified damage value as a percentage of their maximum health.", CVAR_FLAGS );
	g_hCvarType[3] = CreateConVar(		"l4d_shove_handler_type_hunter",		"1",			"1=Deal the damage value specified. 2=Deal the specified damage value as a percentage of their maximum health.", CVAR_FLAGS );
	if( g_bLeft4Dead2 )
	{
	g_hCvarType[4] = CreateConVar(		"l4d_shove_handler_type_spitter",		"1",			"1=Deal the damage value specified. 2=Deal the specified damage value as a percentage of their maximum health.", CVAR_FLAGS );
	g_hCvarType[5] = CreateConVar(		"l4d_shove_handler_type_jockey",		"1",			"1=Deal the damage value specified. 2=Deal the specified damage value as a percentage of their maximum health.", CVAR_FLAGS );
	g_hCvarType[6] = CreateConVar(		"l4d_shove_handler_type_charger",		"1",			"1=Deal the damage value specified. 2=Deal the specified damage value as a percentage of their maximum health.", CVAR_FLAGS );
	}
	g_hCvarType[7] = CreateConVar(		"l4d_shove_handler_type_tank",			"1",			"1=Deal the damage value specified. 2=Deal the specified damage value as a percentage of their maximum health.", CVAR_FLAGS );
	g_hCvarType[8] = CreateConVar(		"l4d_shove_handler_type_witch",			"1",			"1=Deal the damage value specified. 2=Deal the specified damage value as a percentage of their maximum health.", CVAR_FLAGS );

	CreateConVar(						"l4d_shove_handler_version",			PLUGIN_VERSION,	"Shove Handler plugin version.", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	AutoExecConfig(true,				"l4d_shove_handler");

	g_hCvarMPGameMode = FindConVar("mp_gamemode");
	g_hCvarMPGameMode.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModesTog.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModes.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModesOff.AddChangeHook(ConVarChanged_Allow);
	g_hCvarAllow.AddChangeHook(ConVarChanged_Allow);
	g_hCvarBack.AddChangeHook(ConVarChanged_Cvars);
	
	g_hCvarStumble.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarTypes.AddChangeHook(ConVarChanged_Cvars);

	for( int i = 0; i < g_iMaxTypes; i++ )
	{
		g_hCvarCount[i].AddChangeHook(ConVarChanged_Cvars);
		g_hCvarDamage[i].AddChangeHook(ConVarChanged_Cvars);
		g_hCvarType[i].AddChangeHook(ConVarChanged_Cvars);
	}
}

public void OnMapStart()
{
	for( int i = 0; i < sizeof(g_sSounds); i++ )
		PrecacheSound(g_sSounds[i]);

	if( g_bLeft4Dead2 )
		for( int i = 0; i < sizeof(g_sClowns); i++ )
			PrecacheSound(g_sClowns[i]);
}


// ====================================================================================================
//					CVARS
// ====================================================================================================
public void OnConfigsExecuted()
{
	IsAllowed();
}

public void ConVarChanged_Allow(Handle convar, const char[] oldValue, const char[] newValue)
{
	IsAllowed();
}

public void ConVarChanged_Cvars(Handle convar, const char[] oldValue, const char[] newValue)
{
	GetCvars();
}

void GetCvars()
{
	g_bCvarBack = g_hCvarBack.BoolValue;
	g_iCvarStumble = g_hCvarStumble.IntValue;
	g_iCvarTypes = g_hCvarTypes.IntValue;

	for( int i = 0; i < g_iMaxTypes; i++ )
	{
		g_iCvarCount[i] = g_hCvarCount[i].IntValue;
		g_fCvarDamage[i] = g_hCvarDamage[i].FloatValue;
		g_iCvarDamage[i] = g_hCvarType[i].IntValue;
	}
}

void IsAllowed()
{
	bool bCvarAllow = g_hCvarAllow.BoolValue;
	bool bAllowMode = IsAllowedGameMode();
	GetCvars();

	if( g_bCvarAllow == false && bCvarAllow == true && bAllowMode == true )
	{
		g_bCvarAllow = true;
	}

	else if( g_bCvarAllow == true && (bCvarAllow == false || bAllowMode == false) )
	{
		g_bCvarAllow = false;
	}
}

int g_iCurrentMode;
bool IsAllowedGameMode()
{
	if( g_hCvarMPGameMode == null )
		return false;

	int iCvarModesTog = g_hCvarModesTog.IntValue;
	if( iCvarModesTog != 0 )
	{
		g_iCurrentMode = 0;

		int entity = CreateEntityByName("info_gamemode");
		if( IsValidEntity(entity) )
		{
			DispatchSpawn(entity);
			HookSingleEntityOutput(entity, "OnCoop", OnGamemode, true);
			HookSingleEntityOutput(entity, "OnSurvival", OnGamemode, true);
			HookSingleEntityOutput(entity, "OnVersus", OnGamemode, true);
			HookSingleEntityOutput(entity, "OnScavenge", OnGamemode, true);
			ActivateEntity(entity);
			AcceptEntityInput(entity, "PostSpawnActivate");
			if( IsValidEntity(entity) ) // Because sometimes "PostSpawnActivate" seems to kill the ent.
				RemoveEdict(entity); // Because multiple plugins creating at once, avoid too many duplicate ents in the same frame
		}

		if( g_iCurrentMode == 0 )
			return false;

		if( !(iCvarModesTog & g_iCurrentMode) )
			return false;
	}

	char sGameModes[64], sGameMode[64];
	g_hCvarMPGameMode.GetString(sGameMode, sizeof(sGameMode));
	Format(sGameMode, sizeof(sGameMode), ",%s,", sGameMode);

	g_hCvarModes.GetString(sGameModes, sizeof(sGameModes));
	if( sGameModes[0] )
	{
		Format(sGameModes, sizeof(sGameModes), ",%s,", sGameModes);
		if( StrContains(sGameModes, sGameMode, false) == -1 )
			return false;
	}

	g_hCvarModesOff.GetString(sGameModes, sizeof(sGameModes));
	if( sGameModes[0] )
	{
		Format(sGameModes, sizeof(sGameModes), ",%s,", sGameModes);
		if( StrContains(sGameModes, sGameMode, false) != -1 )
			return false;
	}

	return true;
}

public void OnGamemode(const char[] output, int caller, int activator, float delay)
{
	if( strcmp(output, "OnCoop") == 0 )
		g_iCurrentMode = 1;
	else if( strcmp(output, "OnSurvival") == 0 )
		g_iCurrentMode = 2;
	else if( strcmp(output, "OnVersus") == 0 )
		g_iCurrentMode = 4;
	else if( strcmp(output, "OnScavenge") == 0 )
		g_iCurrentMode = 8;
}



// ====================================================================================================
//					SHOVE - SPECIAL INFECTED
// ====================================================================================================
public Action L4D_OnShovedBySurvivor(int client, int victim, const float vecDir[3])
{
	if( !g_bCvarAllow ) return Plugin_Continue;
	if( g_fShove[victim] == GetGameTime() ) return Plugin_Continue; // Sometimes it's called twice in 1 frame -_-

	// L4D2Direct_SetNextShoveTime(client, GetGameTime() + 0.5); // DEBUG

	int type = GetEntProp(victim, Prop_Send, "m_zombieClass");
	if( !g_bLeft4Dead2 && type == 5 ) type = 8;

	// Shoves
	if( g_iCvarCount[type] )
	{
		// Store number of shove hits
		int ref = GetClientUserId(victim);
		if( g_iShoves[victim][INDEX_ENTITY] != ref )
		{
			g_iShoves[victim][INDEX_ENTITY] = ref;
			g_iShoves[victim][INDEX_COUNT] = 0;
		}
	}

	g_iShoves[victim][INDEX_COUNT]++;

	// Kill on shoves
	if( g_iCvarCount[type] && g_iShoves[victim][INDEX_COUNT] >= g_iCvarCount[type] )
	{
		SDKHooks_TakeDamage(victim, client, client, GetEntProp(victim, Prop_Data, "m_iHealth") + 1.0, DMG_CLUB);
		return Plugin_Continue;
	}

	// Damage
	if( g_iCvarTypes & (1 << type - 1) )
	{
		float damage = g_fCvarDamage[type];

		if( damage )
		{
			// Damage scale
			if( g_iCvarDamage[type] == 2 )
			{
				int health = GetEntProp(victim, Prop_Data, "m_iMaxHealth");
				damage *= health / 100;
			}

			SDKHooks_TakeDamage(victim, client, client, damage, DMG_GENERIC); // DMG_CLUB makes their health 1
		}
	}

	// Stumble
	if( g_iCvarStumble & (1 << type) )
	{
		float vPos[3];
		GetClientAbsOrigin(client, vPos);
		L4D_CancelStagger(victim);
		L4D_StaggerPlayer(victim, client, vPos);
	}

	// Block game damage
	SDKHook(victim, SDKHook_OnTakeDamage, OnTakeDamageBlock);
	g_fShove[victim] = GetGameTime();

	// Store health
	g_iShoves[victim][INDEX_HEALTH] = GetEntProp(victim, Prop_Data, "m_iHealth");

	// Reset move type, for some reason this breaks and makes Jockey/Hunter stuck in the air, maybe others if airborne
	RequestFrame(OnFrameMove, GetClientUserId(victim));

	return Plugin_Continue;
}

public void L4D_OnShovedBySurvivor_Post(int client, int victim, const float vecDir[3])
{
	if( g_fShove[victim] == GetGameTime() )
	{
		int type = GetEntProp(victim, Prop_Send, "m_zombieClass");
		if( !g_bLeft4Dead2 && type == 5 ) type = 8;

		if( !(g_iCvarStumble & (1 << type)) )
		{
			L4D_CancelStagger(victim);
		}

		SetEntProp(victim, Prop_Data, "m_iHealth", g_iShoves[victim][INDEX_HEALTH]);
	}
}

public Action OnTakeDamageBlock(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	SDKUnhook(victim, SDKHook_OnTakeDamage, OnTakeDamageBlock);

	if( g_fShove[victim] == GetGameTime() )
	{
		SetEntProp(victim, Prop_Data, "m_iHealth", g_iShoves[victim][INDEX_HEALTH]);
		return Plugin_Handled;
	}

	// For common, not required for SI
	/*
	if( damage == 10000.0 )
	{
		return Plugin_Handled;
	}
	*/

	return Plugin_Continue;
}

void OnFrameMove(int userid)
{
	int client = GetClientOfUserId(userid);
	if( client && IsClientInGame(client) )
	{
		RequestFrame(OnFrameMove2, userid);
	}
}

void OnFrameMove2(int client)
{
	client = GetClientOfUserId(client);
	if( client && IsClientInGame(client) )
	{
		SetEntityMoveType(client, MOVETYPE_WALK);
	}
}



// ====================================================================================================
//					SHOVE - COMMON
// ====================================================================================================
public Action L4D2_OnEntityShoved(int client, int entity, int weapon, float vecDir[3], bool bIsHighPounce)
{
	if( !g_bCvarAllow ) return Plugin_Continue;

	if( entity > 0 && entity <= MaxClients && client > 0 && client <= MaxClients && GetClientTeam(client) == 2 )
	{
		L4D_OnShovedBySurvivor(client, entity, vecDir);
	}
	else if( entity > MaxClients && client > 0 && client <= MaxClients && GetClientTeam(client) == 2 )
	{
		// L4D2Direct_SetNextShoveTime(client, GetGameTime() + 0.5); // DEBUG

		static char classname[10];
		GetEdictClassname(entity, classname, sizeof(classname));

		if( strcmp(classname, "infected") == 0 )
		{
			// Store number of shove hits
			int ref = EntIndexToEntRef(entity);
			if( g_iShoves[entity][INDEX_ENTITY] != ref )
			{
				g_iShoves[entity][INDEX_ENTITY] = ref;
				g_iShoves[entity][INDEX_COUNT] = 0;
				g_iShoves[entity][INDEX_TYPE] = TYPE_COMMON;
			}

			g_iShoves[entity][INDEX_COUNT]++;

			// Damage common
			float damage = g_fCvarDamage[INDEX_COMMON];

			if( g_iCvarTypes & 1 << TYPE_COMMON )
			{
				if( damage )
				{
					// Damage scale
					if( g_iCvarDamage[INDEX_COMMON] == 2 )
					{
						int health = GetEntProp(entity, Prop_Data, "m_iMaxHealth");
						damage *= health;
					}

					// If manually pushing, can't damage before or they won't stumble.. damage is handled by push hurt
					if( g_bCvarBack || g_iShoves[entity][INDEX_COUNT] > 1 )
					{
						SDKHooks_TakeDamage(entity, client, client, damage, DMG_CLUB);
					}
				}
			}

			// Store health
			g_iShoves[entity][INDEX_HEALTH] = GetEntProp(entity, Prop_Data, "m_iHealth");

			// Shove from behind - block first shove -OR- block stumble
			if( (!g_bCvarBack && g_iShoves[entity][INDEX_COUNT] == 1) || !(g_iCvarStumble & (1 << TYPE_COMMON)) )
			{
				if( g_iCvarStumble & (1 << TYPE_COMMON) )
				{
					// Stumble common
					float vPos[3];
					GetClientAbsOrigin(client, vPos);
					PushCommon(client, entity, vPos, damage ? damage : 0.1, TYPE_COMMON);
				}

				// Play hit sound
				if( g_bLeft4Dead2 && GetEntProp(entity, Prop_Send, "m_Gender") == 16 )
				{
					EmitSoundToAll(g_sClowns[GetRandomInt(0, sizeof(g_sClowns) - 1)], entity, SNDCHAN_STATIC);
					Event hEvent = CreateEvent("punched_clown");
					if( hEvent )
					{
						hEvent.SetInt("userid", GetClientUserId(client));
						hEvent.Fire();
					}
				}
				else
				{
					EmitSoundToAll(g_sSounds[GetRandomInt(0, sizeof(g_sSounds) - 1)], entity, SNDCHAN_STATIC);
				}

				g_fShove[entity] = GetGameTime();

				// Block default stumble which can result in death if from behind
				return Plugin_Handled;
			}
		}
		else if( strcmp(classname, "witch") == 0 )
		{
			// Store number of shove hits
			int ref = EntIndexToEntRef(entity);
			if( g_iShoves[entity][INDEX_ENTITY] != ref )
			{
				g_iShoves[entity][INDEX_ENTITY] = ref;
				g_iShoves[entity][INDEX_COUNT] = 0;
				g_iShoves[entity][INDEX_TYPE] = TYPE_WITCH;
			}

			g_iShoves[entity][INDEX_COUNT]++;

			// Kill on shoves
			if( g_iCvarCount[INDEX_COMMON] && g_iShoves[entity][INDEX_COUNT] >= g_iCvarCount[INDEX_WITCH] )
			{
				SDKHooks_TakeDamage(entity, client, client, GetEntProp(entity, Prop_Data, "m_iHealth") + 1.0, DMG_CLUB);
				return Plugin_Continue;
			}

			float damage;

			// Damage Witch
			if( g_iCvarTypes & 1 << TYPE_WITCH )
			{
				damage = g_fCvarDamage[INDEX_WITCH];
	
				if( damage )
				{
					// Damage scale
					if( g_iCvarDamage[INDEX_WITCH] == 2 )
					{
						int health = GetEntProp(entity, Prop_Data, "m_iMaxHealth");
						damage *= health / 100;
					}

					if( !(g_iCvarStumble & (1 << TYPE_WITCH)) )
					{
						SDKHooks_TakeDamage(entity, client, client, damage, DMG_CLUB); // Prevents stumble
					}
				}
			}

			// Stumble Witch
			if( g_iCvarStumble & (1 << TYPE_WITCH) )
			{
				float vPos[3];
				GetClientAbsOrigin(client, vPos);
				PushCommon(client, entity, vPos, damage, TYPE_WITCH);
			}
		}

		g_fShove[entity] = GetGameTime();
	}

	return Plugin_Continue;
}

public void L4D2_OnEntityShoved_Post(int client, int entity, int weapon, float vecDir[3], bool bIsHighPounce)
{
	if( g_bCvarAllow && g_fShove[entity] == GetGameTime() )
	{
		// Restore health that would kill common, or kill if shove count reached
		if( g_iShoves[entity][INDEX_TYPE] == TYPE_COMMON )
		{
			if( !g_iCvarCount[INDEX_COMMON] || g_iShoves[entity][INDEX_COUNT] < g_iCvarCount[INDEX_COMMON] )
			{
				SetEntProp(entity, Prop_Data, "m_iHealth", g_iShoves[entity][INDEX_HEALTH]);
			} else {
				SDKHooks_TakeDamage(entity, client, client, GetEntProp(entity, Prop_Data, "m_iHealth") + 1.0, DMG_CLUB);
			}
		}
	}
}

public void L4D2_OnEntityShoved_PostHandled(int client, int entity, int weapon, float vecDir[3], bool bIsHighPounce)
{
	L4D2_OnEntityShoved_Post(client, entity, weapon, vecDir, bIsHighPounce);
}

void PushCommon(int client, int target, const float vPos[3], float damage, int type)
{
	// Cannot use SDKHooks_TakeDamage because it doesn't push in the correct direction.

	int hurt = CreateEntityByName("point_hurt");
	DispatchKeyValue(hurt, "DamageTarget", "silvershot_shove");
	DispatchSpawn(hurt);

	if( type == TYPE_COMMON && g_bLeft4Dead2 )		DispatchKeyValue(hurt, "DamageType", "33554432");		// DMG_AIRBOAT (1<<25)	// Common L4D2
	else if( type == TYPE_COMMON )					DispatchKeyValue(hurt, "DamageType", "536870912");		// DMG_BUCKSHOT (1<<29)	// Common L4D1
	else if( type == TYPE_WITCH)					DispatchKeyValue(hurt, "DamageType", "64");				// DMG_BLAST (1<<6) // Witch
	else											DispatchKeyValue(hurt, "DamageType", "1");

	static char sTemp[128];
	FloatToString(damage, sTemp, sizeof(sTemp));
	DispatchKeyValue(hurt, "Damage", sTemp);
	GetEntPropString(target, Prop_Data, "m_iName", sTemp, sizeof(sTemp));
	DispatchKeyValue(target, "targetname", "silvershot_shove");
	TeleportEntity(hurt, vPos, NULL_VECTOR, NULL_VECTOR);
	AcceptEntityInput(hurt, "Hurt", client, client);
	DispatchKeyValue(target, "targetname", sTemp);

	RemoveEdict(hurt);
}



// ====================================================================================================
//					DETOURS - MELEE AWARDS BLOCK
// ====================================================================================================
// Prevent "melee_kill" event and awards triggering when not killing common
public MRESReturn OnSwingEnd(int pThis, Handle hReturn)
{
	if( g_bCvarAllow && g_iShoves[pThis][INDEX_COUNT] > 1 && GetGameTime() == g_fShove[pThis] )
	{
		DHookSetReturn(hReturn, 0);
		return MRES_Supercede;
	}

	return MRES_Ignored;
}

public MRESReturn OnAmbushed(int pThis, Handle hParams)
{
	if( g_bCvarAllow && g_iShoves[pThis][INDEX_COUNT] > 1 && GetGameTime() == g_fShove[pThis] )
	{
		return MRES_Supercede;
	}

	return MRES_Ignored;
}