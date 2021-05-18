#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define MAX_SIDES 6
#define ADD_UNITS 10.0
#define DEFAULT_TIMER 10.0
#define FAST_TIMER 1.0
#define ENTITY_MDL "models/props/de_nuke/hr_nuke/nuke_forklift/forklift_tire_02.mdl" // случайная моделька, без разницы какая. она все равно не видна.
#define LASERBEAM "materials/sprites/laserbeam.vmt" // текстура луча

int iInvite[MAXPLAYERS+1], iLaser = -1, iDuels = 0, iMax = 3, iMoney = 2000, iHealth = 100, iPrepareTime = 5, iCount = 5;
bool bReady[MAXPLAYERS+1], bDead = true, bNowDuel = false, bEditMode = false, bRoundEnd = false, bMapHasArena = false;
float fDuelTime = 30.0, fInterval = DEFAULT_TIMER, fBase[2][3], fBounds[MAX_SIDES][2][3], fSpawns[2][3], fDots[2][3];
char sMap[256], sPath[256];

// Массив игроков на дуэли
int iPlayers[2];
#define FOR_PLAYER(%0) for (int %0 = MaxClients; %0 != 0; --%0) if (IsClientInGame(%0) && (%0 == iPlayers[0] || %0 == iPlayers[1]))

Menu mmove, madd;
Handle hTimerZone, hTimerDuel;
ArrayList aArena;

public Plugin myinfo =
{
	name = "aDuels",
	author = "XTANCE",
	description = "Ещё один плагин на дуэльки",
	version = "0.1",
	url = "https://t.me/xtance"
};

public void OnPluginStart()
{
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/aduels.ini");
	
	aArena = new ArrayList(); // энтити пропов для арены
	aArena.Clear();
	OnDuelEnd();
	
	RegAdminCmd("sm_a_edit", Action_Edit, ADMFLAG_ROOT, "Редактировать арену");
	RegAdminCmd("sm_a_spawn", Action_Spawn, ADMFLAG_ROOT, "Спавн");
	RegAdminCmd("sm_a_disable", Action_NoDuel, ADMFLAG_ROOT, "Запретить дуэли на один раунд. Используйте в других плагинах через ServerCommand!");
	
	RegConsoleCmd("sm_a", Action_Duel, "Пригласить на дуэль");
	RegConsoleCmd("sm_d", Action_Duel, "Пригласить на дуэль");
	
	// Эти команды посылаются этим же плагином при начале и конце дуэли
	// Всегда приходит 2 аргумента (userid двух участников)
	RegServerCmd("sm_a_start", Action_OnDuelStart, "Начало дуэли");
	RegServerCmd("sm_a_end", Action_OnDuelEnd, "Конец дуэли");
	
	AddCommandListener(DisableVIP, "sm_vip");
	AddCommandListener(DisableVIP, "sm_viptest");
	AddCommandListener(DisableVIP, "sm_testvip");
	
	mmove = new Menu(hMove);
	mmove.SetTitle("Перемещение");
	mmove.AddItem("x+"," [X+] Вправо ");
	mmove.AddItem("x-"," [X-] Влево  ");
	mmove.AddItem("y+"," [Y+] Вперёд ");
	mmove.AddItem("y-"," [Y-] Назад  ");
	mmove.AddItem("z+"," [Z+] Вверх  ");
	mmove.AddItem("z-"," [Z-] Вниз  ");
	mmove.AddItem("ok","Сохраниться");
	mmove.ExitButton = false;
	mmove.ExitBackButton = true;
	
	madd = new Menu(hAdd);
	madd.SetTitle("Изменение размера\nЗажмите Е для обратной стороны");
	madd.AddItem("x+"," [X+] Вправо ");
	madd.AddItem("x-"," [X-] Влево  ");
	madd.AddItem("y+"," [Y+] Вперёд ");
	madd.AddItem("y-"," [Y-] Назад  ");
	madd.AddItem("z+"," [Z+] Вверх  ");
	madd.AddItem("z-"," [Z-] Вниз  ");
	madd.AddItem("ok","Сохраниться");
	madd.ExitButton = false;
	madd.ExitBackButton = true;
	
	HookEvent("round_start", RoundStart, EventHookMode_Post);
	HookEvent("round_end", RoundEnd, EventHookMode_Post);
	HookEvent("player_death", HookPlayerDeath, EventHookMode_Post);
	HookEvent("player_spawn", HookPlayerSpawn, EventHookMode_Post);
	
	ConVar cvMax = CreateConVar("a_max", "3", "Максимум дуэлей в раунде");
	ConVar cvMoney = CreateConVar("a_money", "2000", "Деньги за выигрыш");
	ConVar cvDead = CreateConVar("a_dead", "1", "Разрешать начинать дуэль мёртвым игрокам");
	ConVar cvTime = CreateConVar("a_time", "30.0", "Время на дуэль");
	
	cvMax.AddChangeHook(HookMax);
	cvMoney.AddChangeHook(HookMoney);
	cvDead.AddChangeHook(HookDead);
	cvTime.AddChangeHook(HookTime);
	
	HookMax(cvMax, "", "");
	HookMoney(cvMoney, "", "");
	HookDead(cvDead, "", "");
	HookTime(cvTime, "", "");

	for (int i = 1; i<= MaxClients; i++) OnClientPostAdminCheck(i);
}

public void HookMax(ConVar cv, const char[] sPrevious, const char[] sCurrent)
{
	iMax = cv.IntValue;
	PrintToServer("[aD] Максимум дуэлей в раунд: %i", iMax);
}

public void HookMoney(ConVar cv, const char[] sPrevious, const char[] sCurrent)
{
	iMoney = cv.IntValue;
	PrintToServer("[aD] Деньги за выигрыш: %i", iMoney);
}

public void HookDead(ConVar cv, const char[] sPrevious, const char[] sCurrent)
{
	bDead = cv.BoolValue;
	PrintToServer("[aD] Разрешено играть мёртвым: %i", bDead);
}

public void HookTime(ConVar cv, const char[] sPrevious, const char[] sCurrent)
{
	fDuelTime = cv.FloatValue;
	PrintToServer("[aD] Время на дуэль: %.2f", fDuelTime);
}

public Action DisableVIP(int iClient, const char[] sCmd, int iArgc)
{
	if (bNowDuel && IsOnDuel(iClient)) RequestFrame(BlockVIP, iClient);
	return Plugin_Continue;
}

void BlockVIP(int i)
{
	Panel panel = new Panel();
	panel.SetTitle("Данная команда недоступна на дуэли!\n");
	panel.DrawItem("Ок :)");
	panel.Send(i, PanelHandler1, 10);
	delete panel;
}

public int PanelHandler1(Menu menu, MenuAction action, int param1, int param2){}

bool Filter(int iEnt, int iMask, any iClient){
	return iClient != iEnt;
}

float GetEyePosition(int iClient)
{
	float fEyePos[3], fEyeAngles[3];
	Handle hTrace; 
	GetClientEyePosition(iClient, fEyePos); 
	GetClientEyeAngles(iClient, fEyeAngles);
	hTrace = TR_TraceRayFilterEx(fEyePos, fEyeAngles, MASK_SOLID, RayType_Infinite, Filter, iClient); 
	TR_GetEndPosition(fEyePos, hTrace); 
	CloseHandle(hTrace);
	return fEyePos;
}

void MainMenu(int iClient){
	
	bEditMode = true;
	
	Menu medit = new Menu(hEdit);
	medit.SetTitle("Редактор арены");
	
	medit.AddItem("pos", "Позиция");
	medit.AddItem("add", "Изменение размеров\n");
	
	char sItem[256];
	FormatEx(sItem, sizeof(sItem), "Выбрать точку 1 (%.0f %.0f %.0f)", fDots[0][0], fDots[0][1], fDots[0][2]); 
	medit.AddItem("dot1", sItem);
	FormatEx(sItem, sizeof(sItem), "Выбрать точку 2 (%.0f %.0f %.0f)", fDots[1][0], fDots[1][1], fDots[1][2]); 
	medit.AddItem("dot2", sItem);
	medit.AddItem("dot_new", "Создать арену между точек");
	medit.AddItem("del", "Удалить арену с карты");
	
	medit.Display(iClient, 0);
}

char sTempArg1[16], sTempArg2[16];

// Пример, как использовать команды sm_a_start и sm_a_end
public Action Action_OnDuelStart(int iArgs)
{
	if (iArgs != 2) return Plugin_Handled;
	
	GetCmdArg(1, sTempArg1, sizeof(sTempArg1));
	GetCmdArg(2, sTempArg2, sizeof(sTempArg2));
	
	PrintToServer("[aD] Началась дуэль между %s и %s (UserID)", sTempArg1, sTempArg2);
	return Plugin_Handled;
}

public Action Action_OnDuelEnd(int iArgs)
{
	if (iArgs != 2) return Plugin_Handled;
	
	GetCmdArg(1, sTempArg1, sizeof(sTempArg1));
	GetCmdArg(2, sTempArg2, sizeof(sTempArg2));
	
	PrintToServer("[aD] Завершена дуэль между %s и %s (UserID)", sTempArg1, sTempArg2);
	return Plugin_Handled;
}

public Action Action_Edit(int iClient, int iArgs){
	MainMenu(iClient);
	return Plugin_Handled;
}

void FindBounds2(float min[3], float max[3]){
	
	if (min[2] > max[2])
	{
		fBounds[0][0] = min;
		min = max;
		max = fBounds[0][0];
	}
	
	//0
	fBounds[0][0] = min;
	fBounds[0][1][0] = max[0];
	fBounds[0][1][1] = max[1];
	fBounds[0][1][2] = min[2] + (max[2] > min[2] ? ADD_UNITS : -ADD_UNITS);
	
	//1
	fBounds[1][0][0] = min[0];
	fBounds[1][0][1] = max[1] - (max[1] < min[1] ? ADD_UNITS : -ADD_UNITS);
	fBounds[1][0][2] = min[2];
	fBounds[1][1] = max;
	
	//2
	fBounds[2][0] = min;
	fBounds[2][1][0] = max[0];
	fBounds[2][1][1] = min[1] + (max[1] > min[1] ? ADD_UNITS : -ADD_UNITS);
	fBounds[2][1][2] = max[2];
	
	//3
	fBounds[3][0] = min;
	fBounds[3][1][0] = min[0] + (max[0] > min[0] ? ADD_UNITS : -ADD_UNITS);
	fBounds[3][1][1] = max[1];
	fBounds[3][1][2] = max[2];
	
	//4
	fBounds[4][0][0] = min[0];
	fBounds[4][0][1] = min[1];
	fBounds[4][0][2] = max[2];
	fBounds[4][1][0] = max[0];
	fBounds[4][1][1] = max[1];
	fBounds[4][1][2] = max[2] + (max[2] < min[2] ? ADD_UNITS : -ADD_UNITS);
	
	//5
	fBounds[5][0] = max;
	fBounds[5][1][0] = max[0] + (max[0] < min[0] ? ADD_UNITS : -ADD_UNITS);
	fBounds[5][1][1] = min[1];
	fBounds[5][1][2] = min[2];
	
	GetMiddleOfABox(fBounds[0][0], fBounds[0][1], fSpawns[0]);
	fSpawns[0][2] += ADD_UNITS;
	fSpawns[1] = fSpawns[0];
	fSpawns[0][0] += 50.0;
	fSpawns[0][1] += 50.0;
	fSpawns[1][0] -= 50.0;
	fSpawns[1][1] -= 50.0;
}

public int hEdit(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			int iClient = param1;
			char sItem[16];
			menu.GetItem(param2, sItem, sizeof(sItem));
			
			if (StrEqual(sItem, "pos", false))
			{
				mmove.Display(iClient, 0);
			}
			else if (StrEqual(sItem, "add", false))
			{
				madd.Display(iClient, 0);
			}
			else if (StrEqual(sItem, "dot1", false))
			{
				fDots[0] = GetEyePosition(iClient);
				MainMenu(iClient);
			}
			else if (StrEqual(sItem, "dot2", false))
			{
				fDots[1] = GetEyePosition(iClient);
				MainMenu(iClient);
			} 
			else if (StrEqual(sItem, "dot_new", false))
			{
				if (fDots[0][0] != 0.0 && fDots[0][1] != 0.0 && fDots[1][1] != 0.0 && fDots[1][1] != 0.0)
				{
					RemoveEntities();
					
					fBase[0] = fDots[0];
					fBase[1] = fDots[1];
					
					if ((bMapHasArena = CheckCoordinates()) == true)
					{
						CreateEntities();
						SetZoneTimer(DEFAULT_TIMER);
					}
					
					Save();
				}
				else
				{
					PrintToChat(iClient, " \x07>>\x01 Вначале отметьте точки.");
				}
				MainMenu(iClient);
			}
			else if (StrEqual(sItem, "del", false))
			{
				fBase[0][0] = fBase[0][1] = fBase[0][2] = fBase[1][0] = fBase[1][1] = fBase[1][2] = 0.0;
				bMapHasArena = false;
				
				Save();
				RemoveEntities();
				SetZoneTimer(0.0);
				PrintToChat(iClient, " \x04>>\x01 Арена удалена!");
			}
		}
		case MenuAction_End:
		{
			bEditMode = false;
			if (bMapHasArena)
			{
				// Если было открыто другое меню, ускорим отрисовку ящиков
				if (param1 == MenuEnd_Selected)
				{
					SetZoneTimer(FAST_TIMER);
					bEditMode = true;
				}
				// Если игрок закрыл меню
				else
				{
					SetZoneTimer(DEFAULT_TIMER);
					CreateBoxes(); // чтобы не ждать 10 сек до срабатывания таймера
				}
			}
			delete menu;
		}
	}
}

public int hMove(Menu menu, MenuAction action, int iClient, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char item[16];
			menu.GetItem(param2, item, sizeof(item));
			int iXYZ, iEnt;
			float fAdd;
			
			if (StrEqual(item, "x+"))
			{
				iXYZ = 0;
				fAdd = ADD_UNITS;
			}
			else if (StrEqual(item, "x-"))
			{
				iXYZ = 0;
				fAdd = -ADD_UNITS;
			}
			else if (StrEqual(item, "y+"))
			{
				iXYZ = 1;
				fAdd = ADD_UNITS;
			}
			else if (StrEqual(item, "y-"))
			{
				iXYZ = 1;
				fAdd = -ADD_UNITS;
			}
			else if (StrEqual(item, "z+"))
			{
				iXYZ = 2;
				fAdd = ADD_UNITS;
			}
			else if (StrEqual(item, "z-"))
			{
				iXYZ = 2;
				fAdd = -ADD_UNITS;
			}
			else if (StrEqual(item, "ok"))
			{
				fAdd = 0.0;
				Save();
				PrintToChat(iClient, " \x04>>\x01 Изменения сохранены!");
			}
			
			mmove.Display(iClient, 0);
			
			if (fAdd != 0.0){
				
				fBase[0][iXYZ]+=fAdd;
				fBase[1][iXYZ]+=fAdd;
				CheckCoordinates();
				
				// Двигаем существующие энтити
				float fPos[3];
				for (int i = 0; i < aArena.Length; i++)
				{
					iEnt = aArena.Get(i);
					if (IsValidEntity(iEnt))
					{
						GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", fPos);
						fPos[iXYZ] += fAdd;
						TeleportEntity(iEnt, fPos, NULL_VECTOR, NULL_VECTOR);
					}
				}
			}
		}
		case MenuAction_Cancel:
		{
			MainMenu(iClient);
		}
	}
}

public int hAdd(Menu menu, MenuAction action, int iClient, int param2){
	switch (action)
	{
		case MenuAction_Select:
		{
			char item[16];
			menu.GetItem(param2, item, sizeof(item));
			int iXYZ;
			float fAdd;
			if (StrEqual(item, "x+"))
			{
				iXYZ = 0;
				fAdd = ADD_UNITS;
			}
			if (StrEqual(item, "x-"))
			{
				iXYZ = 0;
				fAdd = -ADD_UNITS;
			}
			if (StrEqual(item, "y+"))
			{
				iXYZ = 1;
				fAdd = ADD_UNITS;
			}
			if (StrEqual(item, "y-"))
			{
				iXYZ = 1;
				fAdd = -ADD_UNITS;
			}
			if (StrEqual(item, "z+"))
			{
				iXYZ = 2;
				fAdd = ADD_UNITS;
			}
			if (StrEqual(item, "z-"))
			{
				iXYZ = 2;
				fAdd = -ADD_UNITS;
			}
			
			if (StrEqual(item, "ok"))
			{
				PrintToChat(iClient, " \x04>>\x01 Изменения сохранены!");
				fAdd = 0.0;
				Save();
			}
			
			madd.Display(iClient, 0);
			
			if (fAdd != 0.0)
			{
				RemoveEntities();
				if (GetClientButtons(iClient) & IN_USE) fBase[0][iXYZ] += fAdd;
				else fBase[1][iXYZ] += fAdd;
				if (CheckCoordinates()) CreateEntities();
			}
		}
		case MenuAction_Cancel:
		{
			MainMenu(iClient);
		}
	}
}

void Save()
{
	KeyValues kv = new KeyValues("aduels");
	if(kv.ImportFromFile(sPath)) kv.Rewind();
	kv.JumpToKey(sMap, true);
	kv.SetVector("base0", fBase[0]);
	kv.SetVector("base1", fBase[1]);
	kv.Rewind();
	kv.ExportToFile(sPath);
	delete kv;
}

void RemoveEntities()
{
	int iEnt = -1;
	for (int i = 0; i < aArena.Length; i++)
	{
		iEnt = aArena.Get(i);
		if (IsValidEntity(iEnt)) AcceptEntityInput(iEnt, "Kill");
	}
	aArena.Clear();
}

public Action Action_Spawn(int iClient, int iArgs){
	
	if (GetClientTeam(iClient) < CS_TEAM_T)
	{
		ReplyToCommand(iClient, " >> Команда доступна для Т/CT.");
		return Plugin_Handled;
	}
	
	if (!IsPlayerAlive(iClient)) 
	{
		ReplyToCommand(iClient, " >> Команда доступна для живых.");
		return Plugin_Handled;
	}
	
	if (iArgs != 1)
	{
		ReplyToCommand(iClient, " >> Использование: !asp 0/1");
		return Plugin_Handled;
	}
	
	char sSpawn[8];
	GetCmdArgString(sSpawn, sizeof(sSpawn));
	
	if (StrEqual(sSpawn, "0", false))
	{
		TeleportEntity(iClient, fSpawns[0], NULL_VECTOR, NULL_VECTOR);
		ReplyToCommand(iClient, " >> Телепорт на спавн 0");
	}
	else if (StrEqual(sSpawn, "1", false))
	{
		TeleportEntity(iClient, fSpawns[1], NULL_VECTOR, NULL_VECTOR);
		ReplyToCommand(iClient, " >> Телепорт на спавн 1");
	}
	else
	{
		ReplyToCommand(iClient, " >> Использование: !asp 0/1");
	}
	return Plugin_Handled;
}

public void OnMapEnd()
{
   aArena.Clear();
   SetZoneTimer(0.0);
}

public void OnPluginEnd()
{
	RemoveEntities();
	SetZoneTimer(0.0);
}

public void OnMapStart(){
	
	bMapHasArena = bEditMode = bRoundEnd = false;
	
	hTimerZone = hTimerDuel = INVALID_HANDLE;
	aArena.Clear();
	iLaser = PrecacheModel(LASERBEAM, true);
	PrecacheModel(ENTITY_MDL, true);
	
	GetCurrentMap(sMap, sizeof(sMap));
	GetMapDisplayName(sMap, sMap, sizeof(sMap));
	
	KeyValues kv = new KeyValues("aduels");
	if (kv.ImportFromFile(sPath))
	{
		kv.JumpToKey(sMap,true);
		kv.GetVector("base0", fBase[0]);
		kv.GetVector("base1", fBase[1]);
	}
	delete kv;
	
	if ((bMapHasArena = CheckCoordinates()) == true)
	{
		CreateEntities();
		SetZoneTimer(DEFAULT_TIMER);
	}
}

// Устанавливает таймер, отрисовывающий границы арены
void SetZoneTimer(float fInt)
{
	if(hTimerZone != INVALID_HANDLE)
	{
		KillTimer(hTimerZone);
		hTimerZone = INVALID_HANDLE;
	}
	
	if (fInt != 0.0)
	{
		// Эта переменная влияет на таймер повтора и на время отрисовки
		fInterval = fInt;
		hTimerZone = CreateTimer(fInterval, Timer_Zone, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Timer_Zone(Handle timer)
{
	CreateBoxes();
}

void CreateBoxes()
{
	for (int i = 0; i < MAX_SIDES; i++)
	{
		CreateBox(fBounds[i][0], fBounds[i][1]);
	}
}

public Action RoundStart(Event event, const char[] name, bool dontBroadcast){
	bRoundEnd = false;
	aArena.Clear();
	iCount = iDuels = 0;
	OnDuelEnd();
	if (bMapHasArena) CreateEntities();
}

public Action RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	bRoundEnd = true;
}

public Action Action_NoDuel(int iClient, int iArgs){
	bRoundEnd = true;
	ReplyToCommand(iClient, ">> Дуэли отключены на этот раунд!");
	return Plugin_Handled;
}

public Action Action_Duel(int iClient, int iArgs){
	// Если нет аргументов, покажем меню выбора
	if (iArgs < 1)
	{
		Menu mduel = new Menu(hDuel);
		mduel.SetTitle("\nДуэли • %i/%i\nВыберите соперника:", iDuels, iMax);
		mduel.ExitBackButton = true;
		
		char sName[256],sUser[8];
		FormatEx(sName, sizeof(sName), "[%s] Включить автопринятие дуэли", bReady[iClient] ? "✔" : "×");
		
		mduel.AddItem("auto", sName);
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(iClient) != GetClientTeam(i))
			{
				FormatEx(sName, sizeof(sName), "[%s] %N", bReady[i] ? "✔" : (iInvite[i] == iClient ? "✔" : "×"), i);
				IntToString(i, sUser, sizeof(sUser));
				mduel.AddItem(sUser, sName);
			}
		}
		mduel.Display(iClient, MENU_TIME_FOREVER);
	}
	// Попробуем играть дуэль с игроком
	else
	{
		char sArg[16];
		GetCmdArgString(sArg, sizeof(sArg));
		iInvite[iClient] = StringToInt(sArg);
		
		if (CheckLiterallyEverything(iClient, iInvite[iClient]))
		{
			StartDuel(iClient, iInvite[iClient]);
		}
	}
	return Plugin_Handled;
}

public int hDuel(Menu menu, MenuAction action, int iClient, int param2){
	switch (action)
	{
		case MenuAction_Select:
		{
			char item[8];
			menu.GetItem(param2, item, sizeof(item));
			if (StrEqual("auto", item, false))
			{
				bReady[iClient] = !bReady[iClient];
				if (bReady[iClient])
				{
					int iTeam = GetClientTeam(iClient);
					for(int i = 1; i <= MaxClients; i++) if (IsClientInGame(i) && GetClientTeam(i) != iTeam)
					{
						PrintToChat(i, " \x09>>\x01 %N готов к дуэли, начать: \x09/a %i",iClient,iClient);
					}
				}
			}
			else
			{
				int iSomeone = StringToInt(item);
				iInvite[iClient] = iSomeone;
				if (CheckLiterallyEverything(iClient, iInvite[iClient]))
				{
					StartDuel(iClient, iInvite[iClient]);
				}
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

public void OnClientPostAdminCheck(int iClient)
{
	if (IsClientInGame(iClient))
	{
		iInvite[iClient] = -1;
		bReady[iClient] = false;
		SDKHook(iClient, SDKHook_OnTakeDamage, OnTakeDamage);
	}
}

bool IsValidClient(int i)
{
	return (0 < i <= MaxClients && IsClientInGame(i) && !IsFakeClient(i));
}

bool IsDeadClient(int i, int iClient)
{
	if (!bDead && !IsPlayerAlive(i))
	{
		PrintToChat(iClient, " \x02>>\x01 Дуэли могут играть только живые игроки!");
		return false;
	}
	return true;
}

bool CheckLiterallyEverything(int iClient, int iTarget){
	if (!IsValidClient(iClient))
	{
		return false;
	}
	else if (!IsValidClient(iTarget))
	{
		PrintToChat(iClient, " \x07>>\x01 Не получилось начать дуэль с %i", iTarget);
		return false;
	}
	else if (GetClientTeam(iClient) <= 1)
	{
		PrintToChat(iClient, " \x07>>\x01 Дуэли можно играть за T или CT.");
		return false;
	}
	else if ((!IsDeadClient(iClient, iClient)) || !IsDeadClient(iTarget, iClient))
	{
		return false;
	}
	else if (!bMapHasArena)
	{
		PrintToChat(iClient, " \x02>>\x01 На данной карте отсутствует арена.");
		return false;
	}
	else if (bRoundEnd)
	{
		PrintToChat(iClient, " \x02>>\x01 В конце раунда нельзя играть дуэль.");
		return false;
	}
	else if (bEditMode)
	{
		PrintToChat(iClient, " \x02>>\x01 Сейчас проходят техработы.");
		return false;
	}
	else if (GetClientTeam(iClient) == GetClientTeam(iTarget))
	{
		PrintToChat(iClient, " \x02>>\x01 Дуэль можно играть лишь с противником.");
		return false;
	}
	else if (bNowDuel)
	{
		PrintToChat(iClient, " \x02>>\x01 На арене уже есть игроки!");
		return false;
	}
	else if (iDuels >= iMax)
	{
		PrintToChat(iClient, " \x02>>\x01 Максимум дуэлей в раунде: \x02%i!",iDuels);
		return false;
	}
	else if (GameRules_GetProp("m_bWarmupPeriod") == 1)
	{
		PrintToChat(iClient, " \x02>>\x01 На разминке \x02дуэль невозможна!");
		return false;
	}
	else if (!bReady[iTarget] && iInvite[iTarget] != iClient)
	{
		PrintToChat(iClient," \x04>>\x01 Вы пригласили \x04%N\x01 на дуэль!",iTarget);
		PrintToChat(iClient," \x04>>\x01 Он должен написать \x04/a %i\x01, чтобы согласиться.",iClient);
		PrintToChat(iTarget," \x04>>\x01 %N приглашает вас \x04на дуэль!",iClient);
		PrintToChat(iTarget," \x04>>\x01 Напишите \x04/a %i\x01, чтобы согласиться.",iClient);
		return false;
	}
	else
	{
		return true;
	}
}

void StartDuel(int iClient, int iTarget)
{
	iDuels++;
	iPlayers[0] = iClient;
	iPlayers[1] = iTarget;
	
	PrintToChatAll(" \x09>>\x01 Дуэль началась!");
	PrintToChatAll(" \x09>>\x01 %N \x09VS. \x01%N!", iPlayers[0], iPlayers[1]);
	
	iCount = iPrepareTime;
	CreateTimer(1.0, Timer_GetReady, _, TIMER_REPEAT);
	
	// Подготовка к дуэли
	FOR_PLAYER(i)
	{
		// Дроп пушек и бомбы
		int c4;
		while ((c4 = GetPlayerWeaponSlot(i, CS_SLOT_C4)) != -1)
		{
			//Фикс от DarklSide. См. https://hlmod.ru/threads/ispravlenie-oshibki.31038/
			if (GetEntPropEnt(c4, Prop_Send, "m_hOwnerEntity") != i) SetEntPropEnt(c4, Prop_Send, "m_hOwnerEntity", i);
			CS_DropWeapon(i, c4, true, false);
		}
		
		// Респавн, настройка оружия и здоровья
		CS_RespawnPlayer(i);
		TeleportEntity(i, fSpawns[ GetDuelID(i) ], NULL_VECTOR, NULL_VECTOR);
		SetEntPropFloat(i, Prop_Send, "m_flLaggedMovementValue", 0.0);
		SetEntityHealth(i, 1337);
		iInvite[i] = -1;
		FakeClientCommand(i, "use weapon_knife");
	}
	
	bNowDuel = true;
	ServerCommand("sm_a_start %i %i", GetClientUserId(iClient), GetClientUserId(iTarget));
}

// Возвращает 0 или 1 (обычно 0 это тот кто пригласил, а 1 кого пригласили)
int GetDuelID(int iClient)
{
	if (iClient == iPlayers[0]) return 0;
	else if (iClient == iPlayers[1]) return 1;
	else return -1; // этого никогда не должно произойти
}

// Подготовка (вызывается 5 раз)
public Action Timer_GetReady(Handle timer){
	
	// Дуэль прекратилась по какой-то причине (начало нового раунда и т.д.)
	if (!bNowDuel)
	{
		return Plugin_Stop;
	}
	
	// Таймер подготовки истёк
	if (iCount <= 0)
	{
		FOR_PLAYER(i)
		{
			SetEntPropFloat(i, Prop_Send, "m_flLaggedMovementValue", 1.0);
			PrintHintText(i,">> Дуэль началась!!");
			SetEntityHealth(i, iHealth);
		}
		iCount = iPrepareTime;
		if (hTimerDuel != INVALID_HANDLE) KillTimer(hTimerDuel);
		hTimerDuel = CreateTimer(fDuelTime, Timer_Duel);
		return Plugin_Stop;
	}
	
	char sReady[128];
	FormatEx(sReady, sizeof(sReady), ">> Дуэль начнётся через %i секунд!", iCount);
	
	FOR_PLAYER(i)
	{
		SetEntPropFloat(i, Prop_Send, "m_flLaggedMovementValue", 0.0);
		PrintHintText(i,sReady);
		SetEntityHealth(i, 1337);
		ClientCommand(i, "play buttons/button17.wav");
	}
	
	iCount--;
	return Plugin_Continue;
}

bool IsOnDuel(int iClient)
{
	return iClient == iPlayers[0] || iClient == iPlayers[1];
}

public Action Timer_Duel(Handle timer)
{
	hTimerDuel = INVALID_HANDLE;
	FOR_PLAYER(i)
	{
		if (IsPlayerAlive(i)) ForcePlayerSuicide(i);
		PrintToChatAll(" \x03>>\x01 Игрок \x03%N\x01 был убит за задержку дуэли!",i);
	}
}

public Action HookPlayerDeath(Handle event, const char[] sName, bool dontBroadcast)
{
	if (!bNowDuel) return Plugin_Continue;
	
	int iClient = GetClientOfUserId(GetEventInt(event, "userid"));
	if (IsOnDuel(iClient))
	{
		int iEnemy = iPlayers[0];
		if (iEnemy == iClient) iEnemy = iPlayers[1];
		RequestFrame(OnPlayerWon, iEnemy);
		OnDuelEnd();
	}
	return Plugin_Continue;
}

// Конец дуэли
void OnDuelEnd()
{
	// Если дуэль была, пошлём информацию об её конце (можно перехватить другим плагином)
	if (bNowDuel) ServerCommand("sm_a_end %i %i", GetClientUserId(iPlayers[0]), GetClientUserId(iPlayers[1]));
	
	iPlayers[0] = iPlayers[1] = 0;
	bNowDuel = false;
	
	if(hTimerDuel != INVALID_HANDLE)
	{
		KillTimer(hTimerDuel);
		hTimerDuel = INVALID_HANDLE;
	}
}

public Action HookPlayerSpawn(Handle event, const char[] sName, bool dontBroadcast)
{
	if (!bNowDuel) return Plugin_Continue;
	
	int iClient = GetClientOfUserId(GetEventInt(event, "userid"));
	if (IsOnDuel(iClient))
	{
		PrintToChat(iClient, " \x09>>\x01 Респавн во время дуэли запрещён!");
		ForcePlayerSuicide(iClient);
	}
	
	return Plugin_Continue;
}

// Кто-то выиграл
public void OnPlayerWon(int i)
{
	if (!IsValidClient(i)) return;
	
	CS_RespawnPlayer(i);
	SetEntPropFloat(i, Prop_Send, "m_flLaggedMovementValue", 1.0);
	PrintToChatAll(" \x09>>\x01 %N выиграл дуэль.", i);
	
	// Выдача денег
	if (iMoney > 0)
	{
		PrintToChatAll(" \x09>>\x01 Он получил \x09$%i в награду!", iMoney);
		int iStartMoney = GetEntProp(i, Prop_Send, "m_iAccount");
		iStartMoney += iMoney;
		if (iStartMoney > 16000) iStartMoney = 16000;
		SetEntProp(i, Prop_Send, "m_iAccount", iStartMoney);
	}
}

// Обработчик урона
public Action OnTakeDamage(int iVictim, int &iAttacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if (!bNowDuel) return Plugin_Continue;	// не активируемся если вообще нет дуэли
	if (!(0 < iAttacker <= MaxClients)) return Plugin_Continue; // валидность
	if (!(0 < iVictim <= MaxClients)) return Plugin_Continue; // валидность
	
	bool bVictim = IsOnDuel(iVictim);
	bool bAttacker = IsOnDuel(iAttacker);
	
	if (!bVictim && !bAttacker) return Plugin_Continue; // разрешение дамага если оба не на дуэли
	if (bVictim != bAttacker) return Plugin_Handled; // запрет если кто-то из них не играет дуэль
	if (!(damagetype & (DMG_SLASH | DMG_CLUB))) return Plugin_Handled; // запрет если урон не с ножа или рук (weapon_fists)
	if (iCount != iPrepareTime) return Plugin_Handled; // запрет если еще не начата дуэль
	
	return Plugin_Continue;
}

// Проверяет, есть ли координаты для создания арены
bool CheckCoordinates()
{
	if (fBase[0][0] != fBase[1][0] && fBase[0][0] != 0.0 && fBase[0][1] != 0.0 && fBase[0][2] != 0.0)
	{
		FindBounds2(fBase[0], fBase[1]);
		return true;
	}
	else 
	{
		return false;
	}
}

// Спавнит арену
void CreateEntities()
{
	for (int i = 0; i < MAX_SIDES; i++)
	{
		SpawnZone2(fBounds[i][0], fBounds[i][1], i);
	}
}

//from SMLib
int iColor[4] = {0,0,0,255};
void CreateBox(float bottom[3], float upper[3])
{
	if (fInterval < 1.0)
	{
		LogError("CreateBox with %f interval", fInterval);
		return;
	}
	
	iColor[0] = GetRandomInt(0,255);
	iColor[1] = GetRandomInt(0,255);
	iColor[2] = GetRandomInt(0,255);
	
	float corners[8][3];
	int j;
	for (int i = 0; i < 4; i++)
	{
		for (int x=0; x < 3; x++) corners[i][x] = bottom[x];
		for (int x=0; x < 3; x++) corners[i+4][x] = upper[x];
	}

	corners[1][0] = upper[0];
	corners[2][0] = upper[0];
	corners[2][1] = upper[1];
	corners[3][1] = upper[1];
	corners[4][0] = bottom[0];
	corners[4][1] = bottom[1];
	corners[5][1] = bottom[1];
	corners[7][0] = bottom[0];
	
	//bottom
	for (int i = 0; i < 4; i++)
	{
		j = ( i == 3 ? 0 : i+1 );
		TE_SetupBeamPoints(corners[i], corners[j], iLaser, 	0,		//haloindex
															0,		//startframe
															0,		//framerate
															fInterval,	//life
															0.5,	//width
															0.5,	//endwidth
															0,		//fade
															0.0,	//amplitude
															iColor,	//color
															1);		//speed
		TE_SendToAll();
	}
	
	//top
	for (int i = 4; i < 8; i++)
	{
		j = ( i == 7 ? 4 : i+1 );
		TE_SetupBeamPoints(corners[i], corners[j], iLaser, 0,0,0,fInterval,0.5,0.5,0,0.0,iColor,1);
		TE_SendToAll();
	}
	
	//vertical
	for (int i = 0; i < 4; i++)
	{
		TE_SetupBeamPoints(corners[i], corners[i+4], iLaser, 0,0,0,fInterval,0.5,0.5,0,0.0,iColor,1);
		TE_SendToAll();
	}
}

void SpawnZone2(float min[3], float max[3], int z = 0)
{
	int zone = CreateEntityByName("prop_dynamic_override");
	if(zone == -1)
	{
		LogError("Ошибка, не получилось создать зону %i", z);
		return;
	}
	DispatchKeyValue(zone, "solid", "6");
	SetEntityModel(zone, ENTITY_MDL);
	DispatchSpawn(zone);
	ActivateEntity(zone);
	
	float m_vecMins[3], m_vecMaxs[3], middle[3];
	m_vecMins = min;
	m_vecMaxs = max;
	GetMiddleOfABox(m_vecMins, m_vecMaxs, middle);
	TeleportEntity(zone, middle, NULL_VECTOR, NULL_VECTOR);
   
	SetEntityMoveType(zone, MOVETYPE_NONE);
	m_vecMins[0] -= middle[0];
	if (m_vecMins[0] > 0.0) m_vecMins[0] *= -1.0;
	m_vecMins[1] -= middle[1];
	if (m_vecMins[1] > 0.0) m_vecMins[1] *= -1.0;
	m_vecMins[2] -= middle[2];
	if (m_vecMins[2] > 0.0) m_vecMins[2] *= -1.0;
	m_vecMaxs[0] -= middle[0];
	if (m_vecMaxs[0] < 0.0) m_vecMaxs[0] *= -1.0;
	m_vecMaxs[1] -= middle[1];
	if (m_vecMaxs[1] < 0.0) m_vecMaxs[1] *= -1.0;
	m_vecMaxs[2] -= middle[2];
	if (m_vecMaxs[2] < 0.0) m_vecMaxs[2] *= -1.0;
   
	SetEntPropVector(zone, Prop_Send, "m_vecMins", m_vecMins);
	SetEntPropVector(zone, Prop_Send, "m_vecMaxs", m_vecMaxs);
   
	SetEntProp(zone, Prop_Send, "m_usSolidFlags",  0x0010);
	SetEntProp(zone, Prop_Data, "m_nSolidType", 2);
	SetEntProp(zone, Prop_Send, "m_CollisionGroup", 6);
	SetEntProp(zone, Prop_Data, "m_takedamage", 0);
	
	aArena.Push(zone);
   
	int m_fEffects = GetEntProp(zone, Prop_Send, "m_fEffects");
	m_fEffects |= 32;
	SetEntProp(zone, Prop_Send, "m_fEffects", m_fEffects);
	//AcceptEntityInput(zone, "Enable");
}

void GetMiddleOfABox(float vec1[3], float vec2[3], float buffer[3]){
	float mid[3];
	MakeVectorFromPoints(vec1, vec2, mid);
	mid[0] = mid[0] / 2.0;
	mid[1] = mid[1] / 2.0;
	mid[2] = mid[2] / 2.0;
	AddVectors(vec1, mid, buffer);
}
