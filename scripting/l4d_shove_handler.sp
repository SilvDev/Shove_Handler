/*
*	Shove Handler
*	Copyright (C) 2024 Silvers
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



#define PLUGIN_VERSION		"1.13"

/*=======================================================================================
	Plugin Info:

*	Name	:	[L4D & L4D2] Shove Handler
*	Author	:	SilverShot
*	Descrp	:	Overrides the shoving system, allowing to set number of shoves before killing, stumble and damage per bash, for SI and Common.
*	Link	:	https://forums.alliedmods.net/showthread.php?t=337808
*	Plugins	:	https://sourcemod.net/plugins.php?exact=exact&sortby=title&search=1&author=Silvers

========================================================================================
	Change Log:

1.13 (30-Apr-2024)
	- Fixed damage cvars not setting on the correct player classes.
	- To block stumble on Special Infected this plugin requires Left4DHooks version 1.147 or newer.

1.12 (25-Mar-2024)
	- Added cvars "l4d_shove_handler_damage_surv" and "l4d_shove_handler_type_surv" to control Survivor damage on shove.
	- Fixed not being able to free Survivors from Smokers and Jockeys if "l4d_shove_handler_survivor" was set to "0". Thanks to "glhf3000" for reporting.
	- Various changes to fix incorrect damage or cvar settings being followed.

1.11 (07-Nov-2023)
	- L4D1: Fixed not affecting the Tank. Thanks to "ZBzibing" for reporting.
	- Fixed the count cvar not affecting the Witch correctly if the Common count cvar was not enabled.

1.10 (31-Mar-2023)
	- Changed the "l4d_shove_handler_hunter" cvar description to better describe what it does.
	- Fixed the Hunter sometimes not moving after stumbling when shoved. Thanks to "KoMiKoZa" for reporting.

1.9 (10-Mar-2023)
    - Fixed invalid edict errors. Thanks to "Voevoda" for reporting.

1.8 (08-Oct-2022)
	- Added cvar "l4d_shove_handler_survivor" to allow or disallow survivors shoving each other. Requested by "MilanesaTM".

1.7 (04-Aug-2022)
	- Fixed cvar "l4d_shove_handler_hunter" not always working. Thanks to "ZBzibing" for reporting.
	- Fixed the plugin damaging other entities such a GasCans. Thanks to "moschinovac" for reporting.

1.6 (14-Jul-2022)
	- Added cvar "l4d_shove_handler_hunter" to allow or disallow punching an airborne hunter. Requested by "ZBzibing".
	- Code changes that require SourceMod version 1.11.

1.5 (20-Jun-2022)
	- Fixed array index out-of-bounds error. Thanks to "Voevoda" for reporting.

1.4 (03-Jun-2022)
	- Fixed blocking Common Infected stumble not triggering the "entity_shoved" event correctly.
	- This fix will cause the "entity_shoved" event to fire twice, once with the attacker value of "0" and after with the real attacker index.
	- This fixes some plugin conflicts such as "Molotov Shove", "PipeBomb Shove" and "Vomitjar Shove" plugins.

	- Changed the "modes" cvars method to use "Left4DHooks" forwards and natives instead of creating an entity.

1.3 (27-May-2022)
	- Fixed not stumbling Tanks or Witches. Thanks to "Maur0" for reporting.

1.2 (20-May-2022)
	- Fixed the Tank and Witch cvars not being read in L4D1.
	- Fixed SI sometimes being stuck floating. Thanks to "Toranks" for reporting.
	- Fixed array out-of-bounds. Thanks to "Toranks" for reporting.

1.1 (17-May-2022)
	- Fixed blood splatter appearing on shoves when damage is set to 0. Thanks to "Toranks" for reporting.
	- Fixed SI getting stuck when shoved in the air and made to stumble. Thanks to "Toranks" for reporting.

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
#define MAX_CVARS			10

ConVar g_hCvarAllow, g_hCvarMPGameMode, g_hCvarModes, g_hCvarModesOff, g_hCvarModesTog, g_hCvarBack, g_hCvarDeadstop, g_hCvarStumble, g_hCvarSurvivor, g_hCvarTypes, g_hCvarCount[MAX_CVARS], g_hCvarDamage[MAX_CVARS], g_hCvarType[MAX_CVARS];
bool g_bCvarAllow, g_bLeft4Dead2, g_bCvarBack, g_bCvarDeadstop, g_bCvarSurvivor, g_bHookTE;
int g_iCvarStumble, g_iCvarTypes, g_iCvarCount[MAX_CVARS], g_iCvarDamage[MAX_CVARS], g_iClassTank, g_iClassMax;
float g_fCvarDamage[MAX_CVARS];
float g_fShove[2048];		// Shove time
int g_iShoves[2048][4];		// [0] = Entity reference. [1] = Shove count. [2] = Health. [3] = Type

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
	TYPE_SURV		= 256
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
	INDEX_SURV		= 9
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

public void OnAllPluginsLoaded()
{
	ConVar version = FindConVar("left4dhooks_version");
	if( version != null )
	{
		char sVer[8];
		version.GetString(sVer, sizeof(sVer));

		float ver = StringToFloat(sVer);

		if( !g_bLeft4Dead2 && ver < 1.147 )
		{
			LogError("Update Left4DHooks to fix stopping Special Infected from staggering.");
		}

		if( ver >= 1.102 )
		{
			return;
		}
	}

	SetFailState("\n==========\nThis plugin requires \"Left 4 DHooks Direct\" version 1.02 or newer. Please update:\nhttps://forums.alliedmods.net/showthread.php?t=321696\n==========");
}

public void OnPluginStart()
{
	// ====================================================================================================
	// DETOURS
	// ====================================================================================================
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "gamedata/%s.txt", GAMEDATA);
	if( FileExists(sPath) == false ) SetFailState("\n==========\nMissing required file: \"%s\".\nRead installation instructions again.\n==========", sPath);

	GameData hGameData = new GameData(GAMEDATA);
	if( hGameData == null ) SetFailState("Failed to load \"%s.txt\" gamedata.", GAMEDATA);

	// Patch 1
	DynamicDetour hDetour = DynamicDetour.FromConf(hGameData, "CTerrorWeapon::OnSwingEnd");

	if( !hDetour )
		SetFailState("Failed to find \"CTerrorWeapon::OnSwingEnd\" signature.");

	if( !hDetour.Enable(Hook_Pre, OnSwingEnd) )
		SetFailState("Failed to detour \"CTerrorWeapon::OnSwingEnd\".");

	delete hDetour;

	// Patch 2
	hDetour = DynamicDetour.FromConf(hGameData, "Infected::OnAmbushed");

	if( !hDetour )
		SetFailState("Failed to find \"Infected::OnAmbushed\" signature.");

	if( !hDetour.Enable(Hook_Pre, OnAmbushed) )
		SetFailState("Failed to detour \"Infected::OnAmbushed\".");

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
	g_hCvarTypes = CreateConVar(		"l4d_shove_handler_damaged",			"511",			"Who can be damaged when shoved: 0=None, 1=Common, 2=Smoker, 4=Boomer, 8=Hunter, 16=Spitter, 32=Jockey, 64=Charger, 128=Tank, 256=Witch, 512=Survivor. 1023=All. Add numbers together.", CVAR_FLAGS );

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
	g_hCvarDamage[9] = CreateConVar(	"l4d_shove_handler_damage_surv",		"10.0",			"0.0=None (game default). Amount of damage each shove causes. If using percentage type, 100.0 = full health.", CVAR_FLAGS );

	// Hunter deadstop
	g_hCvarDeadstop = CreateConVar(		"l4d_shove_handler_hunter",				"1",			"0=No deadstop. 1=Allow Survivors to shove a hunter that was flying in the air to deadstop it (game default).", CVAR_FLAGS );

	// Stumble
	g_hCvarStumble = CreateConVar(		"l4d_shove_handler_stumble",			"127",			"Stumble when shoved: 0=None, 1=Common, 2=Smoker, 4=Boomer, 8=Hunter, 16=Spitter, 32=Jockey, 64=Charger, 128=Tank (default off), 256=Witch (default off), 512=Survivor (default off). 1023=All. Add numbers together.", CVAR_FLAGS );
	g_hCvarSurvivor = CreateConVar(		"l4d_shove_handler_survivor",			"1",			"0=Block Survivors shoving other Survivors. 1=Allow Survivors to shove each other (game default).", CVAR_FLAGS );

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
	g_hCvarType[9] = CreateConVar(		"l4d_shove_handler_type_surv",			"1",			"1=Deal the damage value specified. 2=Deal the specified damage value as a percentage of their maximum health.", CVAR_FLAGS );

	CreateConVar(						"l4d_shove_handler_version",			PLUGIN_VERSION,	"Shove Handler plugin version.", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	AutoExecConfig(true,				"l4d_shove_handler");

	g_hCvarMPGameMode = FindConVar("mp_gamemode");
	g_hCvarMPGameMode.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModesTog.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModes.AddChangeHook(ConVarChanged_Allow);
	g_hCvarModesOff.AddChangeHook(ConVarChanged_Allow);
	g_hCvarAllow.AddChangeHook(ConVarChanged_Allow);
	g_hCvarBack.AddChangeHook(ConVarChanged_Cvars);
	
	g_hCvarDeadstop.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarStumble.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarSurvivor.AddChangeHook(ConVarChanged_Cvars);
	g_hCvarTypes.AddChangeHook(ConVarChanged_Cvars);

	for( int i = 0; i < MAX_CVARS; i++ )
	{
		if( g_bLeft4Dead2 || (i < 4 || i > 6) || i == 9 )
		{
			if( i != 9 ) g_hCvarCount[i].AddChangeHook(ConVarChanged_Cvars);
			g_hCvarDamage[i].AddChangeHook(ConVarChanged_Cvars);
			g_hCvarType[i].AddChangeHook(ConVarChanged_Cvars);
		}
	}

	g_iClassTank = g_bLeft4Dead2 ? 8 : 5;
	g_iClassMax = g_bLeft4Dead2 ? INDEX_WITCH : INDEX_JOCKEY;
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

void ConVarChanged_Allow(Handle convar, const char[] oldValue, const char[] newValue)
{
	IsAllowed();
}

void ConVarChanged_Cvars(Handle convar, const char[] oldValue, const char[] newValue)
{
	GetCvars();
}

void GetCvars()
{
	g_bCvarBack = g_hCvarBack.BoolValue;
	g_bCvarDeadstop = g_hCvarDeadstop.BoolValue;
	g_iCvarStumble = g_hCvarStumble.IntValue;
	g_bCvarSurvivor = g_hCvarSurvivor.BoolValue;
	g_iCvarTypes = g_hCvarTypes.IntValue;

	for( int i = 0; i < MAX_CVARS; i++ )
	{
		if( g_bLeft4Dead2 || (i < 4 || i > 6) || i == 9 )
		{
			if( i != 9 ) g_iCvarCount[i] = g_hCvarCount[i].IntValue;
			g_fCvarDamage[i] = g_hCvarDamage[i].FloatValue;
			g_iCvarDamage[i] = g_hCvarType[i].IntValue;
		}
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
public void L4D_OnGameModeChange(int gamemode)
{
	g_iCurrentMode = gamemode;
}

bool IsAllowedGameMode()
{
	if( g_hCvarMPGameMode == null )
		return false;

	if( g_iCurrentMode == 0 ) g_iCurrentMode = L4D_GetGameModeType();

	int iCvarModesTog = g_hCvarModesTog.IntValue;

	if( iCvarModesTog && !(iCvarModesTog & g_iCurrentMode) )
		return false;

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



// ====================================================================================================
//					SHOVE - SPECIAL INFECTED
// ====================================================================================================
public Action L4D_OnShovedBySurvivor(int client, int victim, const float vecDir[3])
{
	if( !g_bCvarAllow ) return Plugin_Continue; // Plugin off
	if( g_fShove[victim] == GetGameTime() ) return Plugin_Continue; // Sometimes it's called twice in 1 frame -_-

	// Block survivors shoving each other
	if( !g_bCvarSurvivor && GetClientTeam(client) == 2 && GetClientTeam(victim) == 2 )
	{
		if( GetEntProp(client, Prop_Send, "m_isHangingFromTongue") != 1 && GetEntPropEnt(victim, Prop_Send, "m_tongueOwner") == -1 && GetEntPropEnt(victim, Prop_Send, "m_jockeyAttacker") == -1 )
		{
			return Plugin_Handled;
		}
	}


	// L4D2Direct_SetNextShoveTime(client, GetGameTime() + 0.5); // DEBUG

	int type;
	if( GetClientTeam(victim) == 2 )
	{
		type = INDEX_SURV;
	}
	else
	{
		type = GetEntProp(victim, Prop_Send, "m_zombieClass");
		if( type > g_iClassMax ) return Plugin_Continue;
		if( type == g_iClassTank ) type = 7;
	}



	// Deadstop shoving hunter
	if( type == INDEX_HUNTER && !g_bCvarDeadstop && GetEntPropEnt(victim, Prop_Send, "m_hGroundEntity") == -1 && GetEntProp(victim, Prop_Send, "m_isAttemptingToPounce") )
	{
		return Plugin_Handled;
	}

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
	float damage;

	if( g_iCvarTypes & (1 << type) )
	{
		damage = g_fCvarDamage[type];

		if( damage )
		{
			// Damage scale
			if( g_iCvarDamage[type - 1] == 2 )
			{
				int health = GetEntProp(victim, Prop_Data, "m_iMaxHealth");
				damage *= health / 100;
			}

			SDKHooks_TakeDamage(victim, client, client, damage, DMG_GENERIC); // DMG_CLUB makes their health 1
		}
	}

	if( damage == 0.0 && !g_bHookTE )
	{
		g_bHookTE = true;
		AddTempEntHook("EffectDispatch", OnTempEnt);
	}

	// Stumble
	if( g_iCvarStumble & (1 << type) && type != INDEX_HUNTER ) // Don't allow hunter since it can freeze the infected
	{
		if( GetEntPropEnt(victim, Prop_Send, "m_hGroundEntity") != -1 )
		{
			float vPos[3];
			GetClientAbsOrigin(client, vPos);
			L4D_CancelStagger(victim);
			L4D_StaggerPlayer(victim, client, vPos);
			RequestFrame(OnFrameMove, GetClientUserId(victim));
		}
	}

	// Block game damage
	SDKHook(victim, SDKHook_OnTakeDamage, OnTakeDamageBlock);
	g_fShove[victim] = GetGameTime();

	// Store health
	g_iShoves[victim][INDEX_HEALTH] = GetEntProp(victim, Prop_Data, "m_iHealth");

	if( !(g_iCvarStumble & (1 << type)) )
	{
		L4D_CancelStagger(victim);
	}

	return Plugin_Continue;
}

public void L4D_OnShovedBySurvivor_Post(int client, int victim, const float vecDir[3])
{
	if( g_bCvarAllow && g_fShove[victim] == GetGameTime() )
	{
		if( g_bHookTE )
		{
			g_bHookTE = false;
			RemoveTempEntHook("EffectDispatch", OnTempEnt);
		}

		SetEntProp(victim, Prop_Data, "m_iHealth", g_iShoves[victim][INDEX_HEALTH]);
	}
}

Action OnTakeDamageBlock(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
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

Action OnTempEnt(const char[] te_name, const int[] Players, int numClients, float delay)
{
	if( g_bHookTE )
	{
		g_bHookTE = false;
		RemoveTempEntHook("EffectDispatch", OnTempEnt);
	}

	return Plugin_Handled;
}

void OnFrameMove(int userid)
{
	int client = GetClientOfUserId(userid);
	if( client && IsClientInGame(client) && GetEntPropEnt(client, Prop_Send, "m_hGroundEntity") == -1 )
	{
		RequestFrame(OnFrameMove2, userid);
		SetEntityMoveType(client, MOVETYPE_WALK);
	}
}

void OnFrameMove2(int userid)
{
	int client = GetClientOfUserId(userid);
	if( client && IsClientInGame(client) && GetEntPropEnt(client, Prop_Send, "m_hGroundEntity") == -1 )
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
		return L4D_OnShovedBySurvivor(client, entity, vecDir);
	}
	else if( entity > MaxClients && IsValidEdict(entity) && client > 0 && client <= MaxClients && GetClientTeam(client) == 2 )
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
			float damage;

			if( g_iCvarTypes & 1 << INDEX_COMMON )
			{
				damage = g_fCvarDamage[INDEX_COMMON];

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
			if( (!g_bCvarBack && g_iShoves[entity][INDEX_COUNT] == 1) || !(g_iCvarStumble & (1 << INDEX_COMMON)) )
			{
				if( g_iCvarStumble & (1 << INDEX_COMMON) )
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

				Event hEvent = CreateEvent("entity_shoved");
				if( hEvent )
				{
					hEvent.SetInt("entityid", entity);
					hEvent.SetInt("attacker", GetClientUserId(client));
					hEvent.Fire();
				}

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
			if( g_iCvarCount[INDEX_WITCH] && g_iShoves[entity][INDEX_COUNT] >= g_iCvarCount[INDEX_WITCH] )
			{
				SDKHooks_TakeDamage(entity, client, client, GetEntProp(entity, Prop_Data, "m_iHealth") + 1.0, DMG_CLUB);
				return Plugin_Continue;
			}

			float damage;

			// Damage Witch
			if( g_iCvarTypes & 1 << INDEX_WITCH )
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

					if( !(g_iCvarStumble & (1 << INDEX_WITCH)) )
					{
						SDKHooks_TakeDamage(entity, client, client, damage, DMG_CLUB); // Prevents stumble
					}
				}
			}

			// Stumble Witch
			if( g_iCvarStumble & (1 << INDEX_WITCH) )
			{
				float vPos[3];
				GetClientAbsOrigin(client, vPos);
				PushCommon(client, entity, vPos, damage, TYPE_WITCH);
			}
		}
		else
		{
			g_iShoves[entity][INDEX_TYPE] = -1;
		}

		g_fShove[entity] = GetGameTime();
	}
	else if( entity > MaxClients && entity < 2048 )
	{
		g_iShoves[entity][INDEX_TYPE] = -1;
	}

	return Plugin_Continue;
}

public void L4D2_OnEntityShoved_Post(int client, int entity, int weapon, const float vecDir[3], bool bIsHighPounce)
{
	if( g_bCvarAllow && entity != -1 && g_fShove[entity] == GetGameTime() )
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

// When blocking stumble, trigger the post to reset health or kill
public void L4D2_OnEntityShoved_PostHandled(int client, int entity, int weapon, const float vecDir[3], bool bIsHighPounce)
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
MRESReturn OnSwingEnd(int pThis, DHookReturn hReturn)
{
	if( g_bCvarAllow && g_iShoves[pThis][INDEX_COUNT] > 1 && GetGameTime() == g_fShove[pThis] )
	{
		hReturn.Value = 0;
		return MRES_Supercede;
	}

	return MRES_Ignored;
}

MRESReturn OnAmbushed(int pThis, DHookParam hParams)
{
	if( g_bCvarAllow && g_iShoves[pThis][INDEX_COUNT] > 1 && GetGameTime() == g_fShove[pThis] )
	{
		return MRES_Supercede;
	}

	return MRES_Ignored;
}
