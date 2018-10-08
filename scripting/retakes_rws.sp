#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <kento_csgocolors>

char tags[] = "{ORANGE}[Retake RWS]";
#define PLUGIN_VERSION "1.1"

new String:tablename[] = "rws";

char message[1024]; //Message buffer
char dberror[255]; //database error buffer
Int:PlayerDamage[256];  //Player Damage in 1 Round
Int:PlayerRounds[256]; //Rounds that player joined
Float:rws[256]; //The damage done by player in a session
Float:sessionrws[255]; //Session RWS
new String:SQLError[1024]; //SQL error buffer
Database db;

public Plugin:myinfo = 
{
    name = "[Retake] Round Win Share",
    author = "SoLo",
    description = "A Round Win Share Plugin for retake.",
    version = PLUGIN_VERSION,
    url = "https://hkhbc.com"
}

public OnPluginStart()
{
    RegConsoleCmd("sm_rws", ShowRWS, "[Retake RWS] Check RWS");
    HookEvent("player_hurt", Event_DamageCounter, EventHookMode_Pre);
    HookEvent("player_disconnect", Event_OnDisconnect, EventHookMode_Pre);
    HookEvent("round_start", Event_RoundStart);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("cs_intermission", Event_GameEnd);
    if(SQL_CheckConfig("RRWS")){
        db = SQL_Connect("RRWS", true, dberror, sizeof(dberror));
    }else{
        db = SQL_Connect("default", true, dberror, sizeof(dberror));
    }
    if(db == null){
        LogError("[Retake RWS] Could not connect to database \"default\": %s", dberror);
        return;
    }else{
        PrintToServer("[Retake RWS] Succeed to connect to the database");
        new String:tablequery[512];
        Format( tablequery, sizeof(tablequery), "CREATE TABLE IF NOT EXISTS `%s` ( `id` int(11) NOT NULL AUTO_INCREMENT, `steam` char(255) CHARACTER SET latin1 NOT NULL, `rws` float UNSIGNED NOT NULL DEFAULT '0', `rwscount` int(10) UNSIGNED NOT NULL DEFAULT '0', PRIMARY KEY (`id`)) ENGINE=MyISAM DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;  ", tablename);
        if(SQL_FastQuery( db, tablequery)){
            Format( message, sizeof(message), "[Retake RWS] Succeed to create a table, table name: %s", tablename);
            PrintToServer(message);
        }else{
            SQL_GetError(db, SQLError, sizeof(SQLError));
            Format( message, sizeof(message), "[Retake RWS] Failed to create table, Error: %s", SQLError);
            PrintToServer(message);
        }
    }
    for (int client = 1; client <= MaxClients; client++) {
        if(IsValidClient(client)){
            resetClientRWS(client);
        }
    }
}

public OnClientPutInServer(client){
    resetClientRWS(client);
}

public Action:Event_GameEnd(Event event, const char[] name, bool dontBroadcast){
    PPrintToChatAll("{GREEN}- Match End -");
    PPrintToChatAll("Your RWS has been uploaded to our database.");
    for (int client = 1; client <= MaxClients; client++) {
        if(IsValidClient(client)){
            calcRWS(client);
            PlayerRounds[client] = Int:0;
        }
    }
}

public Action:Event_RoundStart(Event event, const char[] name, bool dontBroadcast) 
{
    for (int client = 1; client <= MaxClients; client++) {
        if(IsValidClient(client)){
            if(!(PlayerRounds[client] > Int:0)){
                PlayerRounds[client] = Int:1;
            }

            sessionrws[client] = rws[client] / float(PlayerRounds[client]);
            Format( message, sizeof(message), "Your RWS in this session: {ORANGE}%0.1f", sessionrws[client]);
            PPrintToChat(client, message);
            PlayerDamage[client] = Int:0;
        }
    }
    return Plugin_Continue;  
} 

public Action:Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) 
{
    int winner = GetEventInt(event, "winner");
    float HighestRWS = 0.0;
    int HighestRWSPlayer = 0;
    new String:HighestRWSPlayerName[128];
    for (int client = 1; client <= MaxClients; client++) {
        if(IsValidClient(client) && GetClientTeam(client) == winner){
            int enemycount;
            int Damage;
            Damage = PlayerDamage[client];
            int playerteam = GetClientTeam(client);
            if(playerteam == 2){
                enemycount = GetTeamClientCount(3);
            }else if(playerteam == 3){
                enemycount = GetTeamClientCount(2);
            }
            if(enemycount == 0){
                enemycount = 1;
            }
            float totalHealth = float(enemycount)*100.0; //getTeamRWS
            float base = Float:(float(Damage)/Float:totalHealth)*100.0; //RWS
            if(base > HighestRWS){
                HighestRWS = base;
                HighestRWSPlayer = client;
            }
            Float:rws[client] = FloatAdd(Float:rws[client], Float:base);
            if(rws[client] > 100.0){
                LogError(message);
            }
        }
        PlayerRounds[client]++;
    }
    if(HighestRWSPlayer > 0){
        GetClientName( HighestRWSPlayer, HighestRWSPlayerName, sizeof(HighestRWSPlayerName))
        Format( message, sizeof(message), "%s has the highest RWS with {ORANGE}%0.1f RWS {NORMAL}in this round!", HighestRWSPlayerName, HighestRWS);
        PPrintToChatAll(message);
    }
    return Plugin_Continue;  
}

public Action:Event_OnDisconnect(Event event, const char[] name, bool dontBroadcast){
    int clientindex;
    int clientid;
    clientid = GetEventInt(event, "userid");
    clientindex = GetClientOfUserId(clientid);
    if(IsValidClient(clientindex)){
        calcRWS(clientindex);
    }
    return Plugin_Handled;
}

public Action:ShowRWS(int client, int args){
    if( args < 1){
        calcSessionRWS( client, client, "Your");
    }else{
        char arg[65];
        GetCmdArg( 1, arg, sizeof(arg));
        char target_name[MAX_TARGET_LENGTH];
        int target_list[MAXPLAYERS], target_count;
        bool tn_is_ml;
        if ((target_count = ProcessTargetString(
                arg,
                client,
                target_list,
                MAXPLAYERS,
                COMMAND_FILTER_NO_MULTI,
                target_name,
                sizeof(target_name),
                tn_is_ml)) <= 0)
        {
            switch (target_count){
                case COMMAND_TARGET_NONE:
                {
                    PPrintToChat(client, "No matching client");
                }
                case COMMAND_TARGET_NOT_ALIVE:
                {
                    PPrintToChat(client, "Target must be alive");
                }
                case COMMAND_TARGET_NOT_DEAD:
                {
                    PPrintToChat(client, "Target must be dead");
                }
                case COMMAND_TARGET_NOT_IN_GAME:
                {
                    PPrintToChat(client, "Target is not in game");
                }
                case COMMAND_TARGET_IMMUNE:
                {
                    PPrintToChat(client, "Unable to target");
                }
                case COMMAND_TARGET_EMPTY_FILTER:
                {
                    PPrintToChat(client, "No matching clients");
                }
                case COMMAND_TARGET_NOT_HUMAN:
                {
                    PPrintToChat(client, "Cannot target bot");
                }
                case COMMAND_TARGET_AMBIGUOUS:
                {
                    PPrintToChat(client, "More than one client matched");
                }
            }
            return Plugin_Handled;
        }
        for (int i = 0; i < target_count; i++)
        {
            calcSessionRWS( client, target_list[i], target_name);
        }
    }
    return Plugin_Handled;
}

void calcSessionRWS(int client,int target, const char[] target_name){
    new String:selectquery[255];
    new String:steamid[255];
    GetClientAuthId( target, AuthId_Steam2, steamid, sizeof(steamid));
    Format(selectquery, sizeof(selectquery), "SELECT rws FROM `%s` WHERE steam = '%s'", tablename, steamid);
    DBResultSet query = SQL_Query(db, selectquery);
    if(query == INVALID_HANDLE){
        SQL_GetError(db, SQLError, sizeof(SQLError));
        PrintToServer(SQLError);
    }else{
        new String:playerrwss[128];
        while(SQL_FetchRow(query)){
            SQL_FetchString(query, 0, playerrwss, sizeof(playerrwss));
        }
        float playerrws = StringToFloat(playerrwss);
        Format( message, sizeof(message), "%s's overall RWS: {ORANGE} %0.1f {NORMAL}| Session RWS: {ORANGE}%0.1f", target_name, playerrws, sessionrws[target]);
        PPrintToChat(client, message);
    }
}

void calcRWS(int client){
    float damage;
    float finalrws;
    damage = rws[client];
    new String:steamid[255];
    GetClientAuthId( client, AuthId_Steam2, steamid, sizeof(steamid));
    if(PlayerRounds[client] <= Int:0){
        LogError("[RWS] Error: Round is 0");
    }else{
        int rwscount = 0;
        float currentrws = 0.0;
        finalrws = damage/float(PlayerRounds[client]);
        new String:selectquery[255];
        Format(selectquery, sizeof(selectquery), "SELECT rws, rwscount FROM `%s` WHERE steam = '%s'", tablename, steamid);
        PrintToServer(selectquery);
        DBResultSet query = SQL_Query(db, selectquery);
        if(query == INVALID_HANDLE){
            SQL_GetError(db, SQLError, sizeof(SQLError));
            PrintToServer(SQLError);
        }
        if(SQL_GetRowCount(query) == 0){
            new String:insertquery[255];
            SQL_GetError(db, SQLError, sizeof(SQLError));
            PrintToServer(SQLError);
            rwscount = 1;
            Format(insertquery, sizeof(insertquery), "INSERT INTO `%s` (steam, rws, rwscount) VALUES ('%s', '%0.01f', '%i')", tablename,steamid, finalrws, rwscount);
            PrintToServer(insertquery);
            DBResultSet insertqueryresult = SQL_Query(db, insertquery);
            if(insertqueryresult == INVALID_HANDLE){
            SQL_GetError(db, SQLError, sizeof(SQLError));
            PrintToServer(SQLError);
            }
        }else{
            new String:temprws[255];
            new String:temprwscount[255];
            new String:updatequery[255];
            while(SQL_FetchRow(query)){
                SQL_FetchString(query, 0, temprws, sizeof(temprws));
                SQL_FetchString(query, 1, temprwscount, sizeof(temprwscount));
            }
            rwscount = StringToInt(temprwscount);
            currentrws = StringToFloat(temprws)*float(rwscount);
            float newtemprws = FloatAdd(finalrws, currentrws);
            int newrwscount = rwscount + 1;
            float newrws = newtemprws/float(newrwscount);
            Format(updatequery, sizeof(updatequery), "UPDATE `%s` SET rws='%0.01f', rwscount='%i' WHERE steam='%s'", tablename, newrws, newrwscount, steamid);
            PrintToServer(updatequery);
            DBResultSet updatequeryresult = SQL_Query(db, updatequery);
            if(updatequeryresult == INVALID_HANDLE){
                SQL_GetError(db, SQLError, sizeof(SQLError));
                PrintToServer(SQLError);
            }
        }
    }
    resetClientRWS(client);
}

void resetClientRWS(int client){
    PPrintToChat( client, "Your Session RWS has been reset.");
    PlayerRounds[client] = Int:1;
    sessionrws[client] = 0.0;
    rws[client] = 0.0;
}

public Action:Event_DamageCounter(Event event, const char[] name, bool dontBroadcast){
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    if(IsValidClient(attacker)){
        int victim = GetClientOfUserId(event.GetInt("userid"));
        int attackerteam = GetClientTeam(attacker);
        int victimteam = GetClientTeam(victim);
        if(attackerteam != victimteam){
            int preDamageHealth = GetClientHealth(victim);
            int donedamage = event.GetInt("dmg_health");
            int postDamageHealth = event.GetInt("health");
            if (postDamageHealth == 0) {
                donedamage += preDamageHealth;
            }
            PlayerDamage[attacker] += Int:donedamage;
        }
    }
}

void PPrintToChat(int client, char[] cmessage){
    char smessage[1024];
    Format(smessage, sizeof(smessage), "%s {NORMAL}%s", tags, cmessage);
    CPrintToChat( client, smessage);
}

void PPrintToChatAll(char[] cmessage){
    char smessage[1024];
    Format(smessage, sizeof(smessage), "%s {NORMAL}%s", tags, cmessage);
    CPrintToChatAll(smessage);
}

stock bool:IsValidClient(client, bool:nobots = true)
{ 
    if (client <= 0 || client > MaxClients || !IsClientConnected(client) || (nobots && IsFakeClient(client)))
    {
        return false; 
    }
    return IsClientInGame(client); 
}  