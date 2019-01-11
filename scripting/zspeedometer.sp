#pragma semicolon 1
#include <sourcemod>
#include <clientprefs>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>

/*
	zee
	zskyworld.com
	2017.05.23	initial
	2017.05.24	added PrintToGameText
	2017.05.25	added cvar, areas, csgo
	2017.05.27	added pause on jump (thanks bogroll <3)
	2017.06.06	added colour, cookies. removed regex
	2017.06.07	added spectator jump support
	2017.06.12	fixed printhinttext & printcentertext stopping loop
	2018.10.27	only offer DisplayAreaCenter on css
	2019.01.11	dont automatically enable when selecting jump/area
*/

public Plugin myinfo = {
	name = "Speedometer",
	author = "z.",
	url = "http://zskyworld.com"
};

enum JumpState {
	JumpStateNo,
	JumpStateYes,
	JumpStateSaved
};

enum DisplayArea {
	DisplayAreaCenter,
	DisplayAreaHint,
	DisplayAreaTopLeft,
	DisplayAreaTopCenter,
	DisplayAreaTopRight,
	DisplayAreaCenterCenter,
	DisplayAreaBottomLeft,
	DisplayAreaBottomRight
};

enum DisplayType {
	DisplayTypeVelocityXY,
	DisplayTypeVelocityXYZ,
	DisplayTypeMPH,
	DisplayTypeKPH
};

enum DisplayColour {
	DisplayColourWhite,
	DisplayColourRed,
	DisplayColourBlue,
	DisplayColourLightBlue,
	DisplayColourGreen,
	DisplayColourPink,
	DisplayColourPurple,
	DisplayColourOrange
};

DisplayArea g_ClientDisplayArea[MAXPLAYERS+1];
DisplayType g_ClientDisplayType[MAXPLAYERS+1];
DisplayColour g_ClientDisplayColour[MAXPLAYERS+1];

bool   g_LateLoaded;
bool   g_IsCSGO;
Handle g_Timer = INVALID_HANDLE;

Handle g_MenuMain = INVALID_HANDLE;
Handle g_MenuArea = INVALID_HANDLE;
Handle g_MenuType = INVALID_HANDLE;
Handle g_MenuColour = INVALID_HANDLE;

Handle g_hEnabledCookie = INVALID_HANDLE;
Handle g_hAreaCookie = INVALID_HANDLE;
Handle g_hTypeCookie = INVALID_HANDLE;
Handle g_hColourCookie = INVALID_HANDLE;
Handle g_hJumpCookie = INVALID_HANDLE;

bool   g_ClientOnOff[MAXPLAYERS+1];
float  g_DisplayRate;
ConVar g_CvarDisplayRate;

bool   g_ClientJumpOnOff[MAXPLAYERS+1];
float  g_JumpTime[MAXPLAYERS+1];
float  g_JumpVel[MAXPLAYERS+1][3];
JumpState g_JumpState[MAXPLAYERS+1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max){
	g_LateLoaded = late;
	return APLRes_Success;
}

public OnPluginStart(){
	char sFolder[8];
	g_IsCSGO = (GetGameFolderName(sFolder, sizeof(sFolder)) > 0 && strcmp(sFolder, "csgo") == 0);

	RegConsoleCmd("sm_speed", SM_Speed);

	g_MenuMain = CreateMenu(MenuMainHandler);
	SetMenuTitle(g_MenuMain, "Speedometer");
	AddMenuItem(g_MenuMain, "onoff", "Display On/Off");
	AddMenuItem(g_MenuMain, "area", "> Select Area");
	AddMenuItem(g_MenuMain, "type", "> Select Type");
	AddMenuItem(g_MenuMain, "colour", "> Select Colour");
	AddMenuItem(g_MenuMain, "jump", "Jump On/Off");

	g_MenuArea = CreateMenu(MenuAreaHandler);
	SetMenuTitle(g_MenuArea, "Speedometer: Area");
	SetMenuExitBackButton(g_MenuArea, true);
	if (!g_IsCSGO){
		AddMenuItem(g_MenuArea, "DisplayAreaCenter", "Center");
	}
	AddMenuItem(g_MenuArea, "DisplayAreaHint", "Hint");
	AddMenuItem(g_MenuArea, "DisplayAreaTopLeft", "TopLeft");
	AddMenuItem(g_MenuArea, "DisplayAreaTopCenter", "TopCenter");
	if (!g_IsCSGO){
		AddMenuItem(g_MenuArea, "DisplayAreaTopRight", "TopRight");
	}
	AddMenuItem(g_MenuArea, "DisplayAreaCenterCenter", "CenterCenter");
	AddMenuItem(g_MenuArea, "DisplayAreaBottomLeft", "BottomLeft");
	if (!g_IsCSGO){
		AddMenuItem(g_MenuArea, "DisplayAreaBottomRight", "BottomRight");
	}

	g_MenuType = CreateMenu(MenuTypeHandler);
	SetMenuTitle(g_MenuType, "Speedometer: Type");
	SetMenuExitBackButton(g_MenuType, true);
	AddMenuItem(g_MenuType, "DisplayTypeVelocityXY", "XY");
	AddMenuItem(g_MenuType, "DisplayTypeVelocityXYZ", "XYZ");
	AddMenuItem(g_MenuType, "DisplayTypeMPH", "MPH");
	AddMenuItem(g_MenuType, "DisplayTypeKPH", "KPH");

	g_MenuColour = CreateMenu(MenuColourHandler);
	SetMenuTitle(g_MenuColour, "Speedometer: Colour");
	SetMenuExitBackButton(g_MenuColour, true);
	AddMenuItem(g_MenuColour, "DisplayColourWhite", "White");
	AddMenuItem(g_MenuColour, "DisplayColourRed", "Red");
	AddMenuItem(g_MenuColour, "DisplayColourBlue", "Blue ");
	AddMenuItem(g_MenuColour, "DisplayColourLightBlue", "Light Blue");
	AddMenuItem(g_MenuColour, "DisplayColourGreen", "Green");
	AddMenuItem(g_MenuColour, "DisplayColourPink", "Pink");
	AddMenuItem(g_MenuColour, "DisplayColourPurple", "Purple");
	AddMenuItem(g_MenuColour, "DisplayColourOrange", "Orange");

	g_hEnabledCookie = RegClientCookie("zspeedo_enabled", "", CookieAccess_Private);
	g_hAreaCookie = RegClientCookie("zspeedo_area", "", CookieAccess_Private);
	g_hTypeCookie = RegClientCookie("zspeedo_type", "", CookieAccess_Private);
	g_hColourCookie = RegClientCookie("zspeedo_colour", "", CookieAccess_Private);
	g_hJumpCookie = RegClientCookie("zspeedo_jump", "", CookieAccess_Private);

	g_CvarDisplayRate = CreateConVar("speedometer_displayrate", "0.1", "Display update rate in seconds", 0, true, 0.01, true, 1.0);
	g_CvarDisplayRate.AddChangeHook(OnDisplayRateChanged);
	OnDisplayRateChanged(g_CvarDisplayRate, "", "");

	HookEvent("player_jump", OnPlayerJump);

	for (int client=1; client<=MaxClients; client++){
		if (IsClientInGame(client)){
			OnClientPutInServer(client);
		}
	}
}

public OnAllPluginsLoaded(){
	if(!g_LateLoaded){
		return;
	}
   
	g_LateLoaded = false;
   
	for (int client = 1; client <= MaxClients; client++){
		if(AreClientCookiesCached(client)){
			OnClientCookiesCached(client);
		}
	}
}

public OnClientPutInServer(client){
	g_JumpState[client] = JumpStateNo;
}

public void OnClientCookiesCached(int client){
	char sEnabled[8], sArea[8], sType[8], sColour[8], sJump[8];
	GetClientCookie(client, g_hEnabledCookie, sEnabled, sizeof(sEnabled));
	GetClientCookie(client, g_hAreaCookie, sArea, sizeof(sArea));
	GetClientCookie(client, g_hTypeCookie, sType, sizeof(sType));
	GetClientCookie(client, g_hColourCookie, sColour, sizeof(sColour));
	GetClientCookie(client, g_hJumpCookie, sJump, sizeof(sJump));

	if(sEnabled[0] == '\0' || strlen(sEnabled) == 0){
		SetClientCookie(client, g_hEnabledCookie, "0");
		SetClientCookie(client, g_hAreaCookie, "3");
		SetClientCookie(client, g_hTypeCookie, "0");
		SetClientCookie(client, g_hColourCookie, "0");
		SetClientCookie(client, g_hJumpCookie, "0");

		sEnabled = "0";
		sArea = "3";
		sType = "0";
		sColour = "0";
		sJump = "0";
	}
 
	g_ClientOnOff[client] = view_as<bool>(StringToInt(sEnabled));
	g_ClientDisplayArea[client] = view_as<DisplayArea>(StringToInt(sArea));
	g_ClientDisplayType[client] = view_as<DisplayType>(StringToInt(sType));
	g_ClientDisplayColour[client] = view_as<DisplayColour>(StringToInt(sColour));
	g_ClientJumpOnOff[client] = view_as<bool>(StringToInt(sJump));
}

public Action SM_Speed(client, args){
	if (0 < client <= MaxClients){
		DisplayMenu(g_MenuMain, client, 30);
	}

	return Plugin_Handled;
}

public MenuMainHandler(Handle menu, MenuAction action, param1, param2){
	if (action == MenuAction_Select && IsClientInGame(param1)){
		char sItem[32];
		GetMenuItem(menu, param2, sItem, sizeof(sItem));
		if (0 == strcmp(sItem, "onoff")){
			g_ClientOnOff[param1] = !g_ClientOnOff[param1];
			PrintToChat(param1, "\x04[Speedometer]:\x01 Display %s",
				g_ClientOnOff[param1]?"On":"Off");

			char sBuffer[8];
			IntToString(view_as<int>(g_ClientOnOff[param1]), sBuffer, sizeof(sBuffer));
			SetClientCookie(param1, g_hEnabledCookie, sBuffer);
		}
		else if (0 == strcmp(sItem, "jump")){
			g_ClientJumpOnOff[param1] = !g_ClientJumpOnOff[param1];
			PrintToChat(param1, "\x04[Speedometer]:\x01 Jump %s",
				g_ClientJumpOnOff[param1]?"On":"Off");

			char sBuffer[8];
			IntToString(view_as<int>(g_ClientJumpOnOff[param1]), sBuffer, sizeof(sBuffer));
			SetClientCookie(param1, g_hJumpCookie, sBuffer);
		}
		else if (0 == strcmp(sItem, "area")){
			DisplayMenu(g_MenuArea, param1, 30);
		}
		else if (0 == strcmp(sItem, "type")){
			DisplayMenu(g_MenuType, param1, 30);
		}
		else if (0 == strcmp(sItem, "colour")){
			DisplayMenu(g_MenuColour, param1, 30);
		}
		else {
			DisplayMenu(menu, param1, 30);
		}
	}
}

public MenuAreaHandler(Handle menu, MenuAction action, param1, param2){
	if (action == MenuAction_Select && IsClientInGame(param1)){
		char sItem[32];
		GetMenuItem(menu, param2, sItem, sizeof(sItem));
		if (0 == strcmp(sItem, "DisplayAreaCenter")){
			g_ClientDisplayArea[param1] = DisplayAreaCenter;
		}
		else if (0 == strcmp(sItem, "DisplayAreaHint")){
			g_ClientDisplayArea[param1] = DisplayAreaHint;
		}
		else if (0 == strcmp(sItem, "DisplayAreaTopLeft")){
			g_ClientDisplayArea[param1] = DisplayAreaTopLeft;
		}
		else if (0 == strcmp(sItem, "DisplayAreaTopCenter")){
			g_ClientDisplayArea[param1] = DisplayAreaTopCenter;
		}
		else if (0 == strcmp(sItem, "DisplayAreaTopRight")){
			g_ClientDisplayArea[param1] = DisplayAreaTopRight;
		}
		else if (0 == strcmp(sItem, "DisplayAreaCenterCenter")){
			g_ClientDisplayArea[param1] = DisplayAreaCenterCenter;
		}
		else if (0 == strcmp(sItem, "DisplayAreaBottomLeft")){
			g_ClientDisplayArea[param1] = DisplayAreaBottomLeft;
		}
		else if (0 == strcmp(sItem, "DisplayAreaBottomRight")){
			g_ClientDisplayArea[param1] = DisplayAreaBottomRight;
		}
		else {
			DisplayMenu(menu, param1, 30);
			return;
		}

		char sBuffer[8];
		IntToString(view_as<int>(g_ClientDisplayArea[param1]), sBuffer, sizeof(sBuffer));
		SetClientCookie(param1, g_hAreaCookie, sBuffer);

		PrintToChat(param1, "\x04[Speedometer]:\x01 Area set to %s", sItem);
		DisplayMenu(g_MenuMain, param1, 30);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack && IsClientInGame(param1)){
		DisplayMenu(g_MenuMain, param1, 30);
	}
}

public MenuTypeHandler(Handle menu, MenuAction action, param1, param2){
	if (action == MenuAction_Select && IsClientInGame(param1)){
		char sItem[32];
		GetMenuItem(menu, param2, sItem, sizeof(sItem));
		if (0 == strcmp(sItem, "DisplayTypeVelocityXY")){
			g_ClientDisplayType[param1] = DisplayTypeVelocityXY;
		}
		else if (0 == strcmp(sItem, "DisplayTypeVelocityXYZ")){
			g_ClientDisplayType[param1] = DisplayTypeVelocityXYZ;
		}
		else if (0 == strcmp(sItem, "DisplayTypeMPH")){
			g_ClientDisplayType[param1] = DisplayTypeMPH;
		}
		else if (0 == strcmp(sItem, "DisplayTypeKPH")){
			g_ClientDisplayType[param1] = DisplayTypeKPH;
		}
		else {
			DisplayMenu(menu, param1, 30);
			return;
		}
		g_ClientOnOff[param1] = true;
		
		char sBuffer[8];
		IntToString(view_as<int>(g_ClientDisplayType[param1]), sBuffer, sizeof(sBuffer));
		SetClientCookie(param1, g_hTypeCookie, sBuffer);

		DisplayMenu(g_MenuMain, param1, 30);
		PrintToChat(param1, "\x04[Speedometer]:\x01 Type set to %s", sItem);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack && IsClientInGame(param1)){
		DisplayMenu(g_MenuMain, param1, 30);
	}
}

public MenuColourHandler(Handle menu, MenuAction action, param1, param2){
	if (action == MenuAction_Select && IsClientInGame(param1)){
		char sItem[32];
		GetMenuItem(menu, param2, sItem, sizeof(sItem));
		if (0 == strcmp(sItem, "DisplayColourWhite")){
			g_ClientDisplayColour[param1] = DisplayColourWhite;
		}
		else if (0 == strcmp(sItem, "DisplayColourRed")){
			g_ClientDisplayColour[param1] = DisplayColourRed;
		}
		else if (0 == strcmp(sItem, "DisplayColourBlue")){
			g_ClientDisplayColour[param1] = DisplayColourBlue;
		}
		else if (0 == strcmp(sItem, "DisplayColourLightBlue")){
			g_ClientDisplayColour[param1] = DisplayColourLightBlue;
		}
		else if (0 == strcmp(sItem, "DisplayColourGreen")){
			g_ClientDisplayColour[param1] = DisplayColourGreen;
		}
		else if (0 == strcmp(sItem, "DisplayColourPink")){
			g_ClientDisplayColour[param1] = DisplayColourPink;
		}
		else if (0 == strcmp(sItem, "DisplayColourPurple")){
			g_ClientDisplayColour[param1] = DisplayColourPurple;
		}
		else if (0 == strcmp(sItem, "DisplayColourOrange")){
			g_ClientDisplayColour[param1] = DisplayColourOrange;
		}
		else {
			DisplayMenu(menu, param1, 30);
			return;
		}
		
		char sBuffer[8];
		IntToString(view_as<int>(g_ClientDisplayColour[param1]), sBuffer, sizeof(sBuffer));
		SetClientCookie(param1, g_hColourCookie, sBuffer);

		DisplayMenu(g_MenuMain, param1, 30);
		PrintToChat(param1, "\x04[Speedometer]:\x01 Colour set to %s", sItem);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack && IsClientInGame(param1)){
		DisplayMenu(g_MenuMain, param1, 30);
	}
}

public Action OnTimer(Handle timer){
	char sOutput[64];
	float fVel[3], fArea[2];
	for (int client=1; client<=MaxClients; client++){
		if (IsClientInGame(client)){
			GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVel);

			switch (g_JumpState[client]){
				case JumpStateSaved:
				{
					if (GetEngineTime() > g_JumpTime[client] + 2.0){
						g_JumpState[client] = JumpStateNo;
					}
				}
				case JumpStateNo:
				{
				}
				case JumpStateYes:
				{
					g_JumpState[client] = JumpStateSaved;
					g_JumpVel[client] = fVel;
				}
			}
		}

		if (IsClientInGame(client) && g_ClientOnOff[client]){
			int iTarget = client;
			if (!IsPlayerAlive(client) || IsClientObserver(client)){
				int iSpecMode = GetEntProp(client, Prop_Send, "m_iObserverMode");
				if (iSpecMode == 4 || iSpecMode == 5)
				{
					iTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
				}
			}

			if (iTarget <= 0 || iTarget > MaxClients)
				iTarget = client;

			if (!IsClientInGame(iTarget))
				iTarget = client;

			switch (g_ClientDisplayType[client]){
				case DisplayTypeVelocityXY:
				{
					if (g_ClientJumpOnOff[client] && g_JumpState[iTarget] == JumpStateSaved){
						Format(sOutput, sizeof(sOutput), "%.1f\n%.1f",
							SquareRoot((fVel[0] * fVel[0]) + (fVel[1] * fVel[1])),
							SquareRoot((g_JumpVel[iTarget][0] * g_JumpVel[iTarget][0]) + (g_JumpVel[iTarget][1] * g_JumpVel[iTarget][1])));
					}
					else {
						Format(sOutput, sizeof(sOutput), "%.1f",
							SquareRoot((fVel[0] * fVel[0]) + (fVel[1] * fVel[1])));
					}
				}
				case DisplayTypeVelocityXYZ:
				{
					if (g_ClientJumpOnOff[client] && g_JumpState[iTarget] == JumpStateSaved){
						Format(sOutput, sizeof(sOutput), "%.1f\n%.1f",
							SquareRoot((fVel[0] * fVel[0]) + (fVel[1] * fVel[1]) + (fVel[2] * fVel[2])),
							SquareRoot((g_JumpVel[iTarget][0] * g_JumpVel[iTarget][0]) + (g_JumpVel[iTarget][1] * g_JumpVel[iTarget][1]) + (g_JumpVel[iTarget][2] * g_JumpVel[iTarget][2])));
					}
					else {
						Format(sOutput, sizeof(sOutput), "%.1f",
							SquareRoot((fVel[0] * fVel[0]) + (fVel[1] * fVel[1]) + (fVel[2] * fVel[2])));
					}
				}
				case DisplayTypeMPH:
				{
					if (g_ClientJumpOnOff[client] && g_JumpState[iTarget] == JumpStateSaved){
						Format(sOutput, sizeof(sOutput), "%.1f\n%.1f",
							(SquareRoot((fVel[0] * fVel[0]) + (fVel[1] * fVel[1]) + (fVel[2] * fVel[2])) / 26.0),
							(SquareRoot((g_JumpVel[iTarget][0] * g_JumpVel[iTarget][0]) + (g_JumpVel[iTarget][1] * g_JumpVel[iTarget][1]) + (g_JumpVel[iTarget][2] * g_JumpVel[iTarget][2])) / 26.0));
					}
					else {
						Format(sOutput, sizeof(sOutput), "%.1f",
							SquareRoot((fVel[0] * fVel[0]) + (fVel[1] * fVel[1]) + (fVel[2] * fVel[2])) / 26.0);
					}
				}
				case DisplayTypeKPH:
				{
					if (g_ClientJumpOnOff[client] && g_JumpState[iTarget] == JumpStateSaved){
						Format(sOutput, sizeof(sOutput), "%.1f\n%.1f",
							((SquareRoot((fVel[0] * fVel[0]) + (fVel[1] * fVel[1]) + (fVel[2] * fVel[2])) / 26.0) * 1.609),
							((SquareRoot((g_JumpVel[iTarget][0] * g_JumpVel[iTarget][0]) + (g_JumpVel[iTarget][1] * g_JumpVel[iTarget][1]) + (g_JumpVel[iTarget][2] * g_JumpVel[iTarget][2])) / 26.0) * 1.609));
					}
					else {
						Format(sOutput, sizeof(sOutput), "%.1f",
							(SquareRoot((fVel[0] * fVel[0]) + (fVel[1] * fVel[1]) + (fVel[2] * fVel[2])) / 26.0) * 1.609);
					}
				}
				default:
				{
					continue;
				}
			}

			switch (g_ClientDisplayArea[client]){
				case DisplayAreaCenter:
				{
					PrintCenterText(client, sOutput);
					continue;
				}
				case DisplayAreaHint:
				{
					PrintHintText(client, sOutput);
					if (!g_IsCSGO){
						StopSound(client, SNDCHAN_STATIC, "UI/hint.wav");
					}
					continue;
				}
				case DisplayAreaTopLeft:
				{
					fArea[0] = 0.0;
					fArea[1] = 0.0;
				}
				case DisplayAreaTopCenter:
				{
					fArea[0] = -1.0;
					fArea[1] = 0.2;
				}
				case DisplayAreaTopRight:
				{
					fArea[0] = 1.0;
					fArea[1] = 0.0;
				}
				case DisplayAreaCenterCenter:
				{
					fArea[0] = -1.0;
					fArea[1] = -1.0;
				}
				case DisplayAreaBottomLeft:
				{
					fArea[0] = 0.0;
					fArea[1] = 1.0;
				}
				case DisplayAreaBottomRight:
				{
					fArea[0] = 1.0;
					fArea[1] = 1.0;
				}
			}

			switch (g_ClientDisplayColour[client]){
				case DisplayColourWhite:
				{
					PrintToGameText(client, sOutput, fArea[0], fArea[1], {255, 255, 255});
				}
				case DisplayColourRed:
				{
					PrintToGameText(client, sOutput, fArea[0], fArea[1], {235, 49, 49});
				}
				case DisplayColourBlue:
				{
					PrintToGameText(client, sOutput, fArea[0], fArea[1], {60, 45, 235});
				}
				case DisplayColourLightBlue:
				{
					PrintToGameText(client, sOutput, fArea[0], fArea[1], {38, 181, 237});
				}
				case DisplayColourGreen:
				{
					PrintToGameText(client, sOutput, fArea[0], fArea[1], {39, 194, 59});
				}
				case DisplayColourPink:
				{
					PrintToGameText(client, sOutput, fArea[0], fArea[1], {242, 17, 216});
				}
				case DisplayColourPurple:
				{
					PrintToGameText(client, sOutput, fArea[0], fArea[1], {163, 25, 209});
				}
				case DisplayColourOrange:
				{
					PrintToGameText(client, sOutput, fArea[0], fArea[1], {227, 151, 11});
				}
			}
		}
	}
}

public PrintToGameText(int client, char[] msg, float sx, float sy, int colour[3]){
	SetHudTextParams(sx, sy, g_DisplayRate, colour[0], colour[1], colour[2], 255, 0, 0.0, 0.0, 0.0);
	ShowHudText(client, -1, msg);
}

public void OnDisplayRateChanged(ConVar convar, char[] oldValue, char[] newValue){
	g_DisplayRate = convar.FloatValue;
	if (g_Timer != INVALID_HANDLE){
		KillTimer(g_Timer);
	}
	g_Timer = CreateTimer(g_DisplayRate, OnTimer, _, TIMER_REPEAT);
}

public Action OnPlayerJump(Handle event, char[] name, bool dontBroadcast){
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client > 0 && client <= MaxClients){
		g_JumpTime[client] = GetEngineTime();
		g_JumpState[client] = JumpStateYes;
	}
	return Plugin_Continue;
}
