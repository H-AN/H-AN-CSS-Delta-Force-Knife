#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <HanWeaponSystem>

public Plugin myinfo =
{
    name = "[H-AN]CS起源三角洲刀具 Delta Force Knife",
    author = "华仔 H-AN",
    description = "华仔 H-AN 三角洲风格刀具通用驱动插件(北极星等, 组配置驱动)",
    version = "1.7",
    url = "[H-AN]武器系统三角洲, QQ群107866133, github https://github.com/H-AN"
};

#define SNDCHAN_KNIFE SNDCHAN_STATIC

#define EF_NODRAW 32     // 引擎效果位: 隐藏渲染(与武器系统/QuickMelee 使用的值一致)

// ======================== 常量 ========================
#define MAX_DFKNIVES     32      // 最多支持的刀具组数量
#define MAX_RIGHT_SEQ    4       // 右键动画序列列表最大数量
#define LEFT_COMBO_COUNT 3       // 左键连招段数(固定三刀)

// ======================== ConVars ========================
// 组参数全部走 configs/DeltaForceKnife.cfg, 只有总开关和音效开关走 CVar
ConVar g_hEnableCvar;
ConVar g_hSoundEnableCvar;
ConVar g_hOldWeaponFix;

bool g_bEnable;
bool g_bSoundEnable;

// ======================== 刀具组配置 ========================
// 每个组 = 一把三角洲风格武器, 只填写进组的武器会被驱动
enum struct DeltaKnifeCfg
{
    char sClassName[64];                        // 武器实体名称(统一小写)

    float fIdleTimeout;                         // 连招空闲超时, 超过则连招重置

    int iLeftSeq[LEFT_COMBO_COUNT];             // 左键三刀 QC 序列号
    int iLeftFrames[LEFT_COMBO_COUNT];          // 左键三刀动画总帧数(传给武器系统, 动画持续时长 = 帧数/30, 不参与音效)
    int iLeftFps[LEFT_COMBO_COUNT];             // 左键三刀动画 fps(转刀音效帧号换算用, 缺省 66)
    float fLeftInterval[LEFT_COMBO_COUNT];      // 该刀之后到下一刀的间隔 [0]=一->二 [1]=二->三 [2]=三->一
    float fLeftDamage[LEFT_COMBO_COUNT];        // 左键三刀基础伤害

    int iRightSeq[MAX_RIGHT_SEQ];               // 右键 QC 序列号列表(1个=固定, 多个=交替循环)
    int iRightSeqCount;                         // 右键序列实际数量
    int iRightFrames;                           // 右键动画总帧数(传给武器系统, 不参与音效)
    int iRightFps;                              // 右键动画 fps(转刀音效帧号换算用, 缺省 66)
    float fRightInterval;                       // 右键攻击间隔
    float fRightDamage;                         // 右键基础伤害

    float fHeadshotMultiplier;                  // 爆头伤害倍率

    int iRotateFrame[LEFT_COMBO_COUNT];         // 左键各刀转刀起始帧(对应 RotateSound1~3 的帧号部分, 纯路径=0 即立即播放)
    char sRotateSound1[PLATFORM_MAX_PATH];      // 左键第一刀转刀音效 "帧号:路径" 或 "路径"(留空不播)
    char sRotateSound2[PLATFORM_MAX_PATH];      // 左键第二刀
    char sRotateSound3[PLATFORM_MAX_PATH];      // 左键第三刀
    int iRightRotateFrame;                      // 右键转刀起始帧(对应 RightRotateSound 的帧号部分)
    char sRightRotateSound[PLATFORM_MAX_PATH];  // 右键转刀音效 "帧号:路径" 或 "路径"(留空不播)

    int iDrawSeq2;                              // 特殊切换 QC 序列号(-1 = 双切换功能关闭)
    int iDrawFrames2;                           // 特殊切换动画总帧数(状态时长 = 帧数/30, 须覆盖整个 draw)
    char sDrawSound1[PLATFORM_MAX_PATH];        // 普通切换音效(走同步 draw 时播放, 留空不播)
    char sDrawSound2[PLATFORM_MAX_PATH];        // 特殊切换音效(走特殊 draw 时播放, 留空不播)

    char sHitSound[PLATFORM_MAX_PATH];          // 普通命中音(留空不播)
    char sKillSound[PLATFORM_MAX_PATH];         // 普通击杀音(留空不播)
    char sHeadshotSound[PLATFORM_MAX_PATH];     // 爆头击杀音(留空不播)
}

DeltaKnifeCfg g_Knives[MAX_DFKNIVES];
int g_iKnifeCount = 0;
StringMap g_hClassMap = null;                   // classname(小写) -> 组索引

// ======================== 玩家状态数组 ========================
int g_iAttackID[MAXPLAYERS + 1];                            // 攻击计数, 用于作废旧攻击的延迟音Timer
int g_iLeftPhase[MAXPLAYERS + 1];                           // 左键连招段 0~2
int g_iRightPhase[MAXPLAYERS + 1];                          // 右键交替序号
int g_iCurrentAttackPhase[MAXPLAYERS + 1];                  // 当前攻击段位(0~2=左键 3=右键), 伤害查表用
int g_iKnifeIndex[MAXPLAYERS + 1];                          // 当前连招所属刀具组索引
float g_fLastAttackTime[MAXPLAYERS + 1];                    // 上次攻击时间, 空闲超时判断
int g_iLastKnifeHitGroup[MAXPLAYERS + 1][MAXPLAYERS + 1];   // victim x attacker 最近命中部位(击杀音判断)

// ======================== 插件生命周期 ========================
public void OnPluginStart()
{
    CreateDeltaKnifeCVars();

    RegAdminCmd("sm_deltaforce_knife_reload", CmdReload, ADMFLAG_CONFIG, "重载三角洲刀具配置(configs/DeltaForceKnife.cfg)");

    AddTempEntHook("PlayerAnimEvent", EventPlayerAnim);
    HookEvent("player_hurt", EventPlayerHurt, EventHookMode_Pre);
    HookEvent("player_death", EventPlayerDeath, EventHookMode_Pre);
    HookEvent("player_spawn", EventPlayerSpawn, EventHookMode_Post);
}

public void OnAllPluginsLoaded()
{
    if (LibraryExists("HanWeaponSystem"))
    {
        PrintToServer("[H-AN] HanWeaponSystem 已加载, Delta Force Knife API 就绪");

        // 获取 HanWeaponSystem 的旧武器修复 Cvar
        g_hOldWeaponFix = FindConVar("han_oldweaponfix");

        if (g_hOldWeaponFix != null)
        {
            PrintToServer("[H-AN] 已获取 han_oldweaponfix");
        }
        else
        {
            PrintToServer("[H-AN] 警告：无法找到 han_oldweaponfix");
        }
    }
}

public void OnMapStart()
{
    LoadConfig();
    PrecacheSounds();
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_TraceAttack, TraceAttack);

    // 双切换动画检测: 与武器系统 switchsound 同源同款钩子(切换 + 拾取/出生都算掏出)
    SDKHook(client, SDKHook_WeaponSwitch, OnKnifeSwitch);
    SDKHook(client, SDKHook_WeaponEquip, OnKnifeSwitch);
}

// ============================================================================
// 掏刀检测(武器切换/拾取): 推迟一帧等武器系统完成 VM 换模后再处理
// ============================================================================
public Action OnKnifeSwitch(int client, int weapon)
{
    if (!g_bEnable)
        return Plugin_Continue;

    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Continue;

    // 设计: 任何武器切换都重置连招状态(含作废未播的延迟音效/延迟动画),
    // 切走再切回三角洲刀后必定从第一刀开始
    ResetPlayerState(client);

    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));

    CreateTimer(0.0, Timer_KnifeDraw, pack, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);

    return Plugin_Continue;
}

// ============================================================================
// 掏刀处理: 当前武器为启用双切换的刀时, 50% 普通切换(不干预动画, 播普通音效),
// 50% 特殊切换(自定义动画压过同步 + 播特殊音效)
// ============================================================================
public Action Timer_KnifeDraw(Handle timer, DataPack pack)
{
    pack.Reset();

    int client = GetClientOfUserId(pack.ReadCell());

    if (client <= 0 ||
        client > MaxClients ||
        !IsClientInGame(client) ||
        !IsPlayerAlive(client))
    {
        return Plugin_Stop;
    }

    int active = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (active <= 0 || !IsValidEntity(active))
        return Plugin_Stop;

    int idx = GetKnifeIndexByWeapon(active);
    if (idx == -1 || g_Knives[idx].iDrawSeq2 == -1)
        return Plugin_Stop;

    // 50/50: 0 = 普通切换, 1 = 特殊切换
    if (GetRandomInt(0, 1) == 0)
    {
        // 普通切换: 动画不干预(武器系统同步照常)
        if (g_bSoundEnable && strlen(g_Knives[idx].sDrawSound1) > 0)
        {
            EmitSoundToAll(g_Knives[idx].sDrawSound1, client, SNDCHAN_WEAPON, SNDLEVEL_NORMAL);
        }
        return Plugin_Stop;
    }

    // 特殊切换: 期间玩家已出刀(攻击动画在播) → 攻击优先, 放弃特殊切换
    if (Han_IsClientCustomAnim(client))
        return Plugin_Stop;

    // 特殊切换动画(带同序列重播保护, attackToken=0 = 掏刀路径)
    StartCustomAnimSafe(client, g_Knives[idx].iDrawSeq2, g_Knives[idx].iDrawFrames2, 0);

    if (g_bSoundEnable && strlen(g_Knives[idx].sDrawSound2) > 0)
    {
        EmitSoundToAll(g_Knives[idx].sDrawSound2, client, SNDCHAN_WEAPON, SNDLEVEL_NORMAL);
    }

    return Plugin_Stop;
}

public void OnClientDisconnect(int client)
{
    ResetPlayerState(client);
}

// ======================== 伤害接管 ========================
public Action TraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
    if (!g_bEnable)
        return Plugin_Continue;

    if (attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker) || !IsPlayerAlive(attacker))
        return Plugin_Continue;

    int weapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
    if (weapon <= 0 || !IsValidEntity(weapon))
        return Plugin_Continue;

    int idx = GetKnifeIndexByWeapon(weapon);
    if (idx == -1)
        return Plugin_Continue;

    // 连招状态必须属于当前这把刀, 防止换刀后误用旧段位伤害
    if (g_iKnifeIndex[attacker] != idx)
        return Plugin_Continue;

    float baseDamage;
    switch (g_iCurrentAttackPhase[attacker])
    {
        case 0:
        {
            baseDamage = g_Knives[idx].fLeftDamage[0];
        }

        case 1:
        {
            baseDamage = g_Knives[idx].fLeftDamage[1];
        }

        case 2:
        {
            baseDamage = g_Knives[idx].fLeftDamage[2];
        }

        case 3:
        {
            baseDamage = g_Knives[idx].fRightDamage;
        }

        default:
        {
            return Plugin_Continue;
        }
    }

    float pos[3], ang[3];
    GetClientEyePosition(attacker, pos);
    GetClientEyeAngles(attacker, ang);

    TR_TraceRayFilter(pos, ang, MASK_SHOT, RayType_Infinite, Trace_HitVictimOnly, victim);
    int Hitgroup = TR_GetHitGroup();

    // 命中头部(1)或射线未命中(0)按爆头计算, 与北极星逻辑一致
    if (Hitgroup == 1 || Hitgroup == 0)
    {
        damage = baseDamage * g_Knives[idx].fHeadshotMultiplier;
    }
    else
    {
        damage = baseDamage;
    }

    return Plugin_Changed;
}

// ======================== 玩家状态管理 ========================
void ResetPlayerState(int client)
{
    g_iAttackID[client] = 0;
    g_iLeftPhase[client] = 0;
    g_iRightPhase[client] = 0;
    g_iCurrentAttackPhase[client] = 0;
    g_iKnifeIndex[client] = -1;
    g_fLastAttackTime[client] = 0.0;
}

void StopKnifeSounds(int client, int idx)
{
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
        return;

    if (idx < 0 || idx >= g_iKnifeCount)
        return;

    if (strlen(g_Knives[idx].sRotateSound1) > 0)
        StopSound(client, SNDCHAN_KNIFE, g_Knives[idx].sRotateSound1);
    if (strlen(g_Knives[idx].sRotateSound2) > 0)
        StopSound(client, SNDCHAN_KNIFE, g_Knives[idx].sRotateSound2);
    if (strlen(g_Knives[idx].sRotateSound3) > 0)
        StopSound(client, SNDCHAN_KNIFE, g_Knives[idx].sRotateSound3);
    if (strlen(g_Knives[idx].sRightRotateSound) > 0)
        StopSound(client, SNDCHAN_KNIFE, g_Knives[idx].sRightRotateSound);
}

// ======================== 动画强制 ========================
void ForceAttackAnimation(int client, int sequence, int frames)
{
    int vm0 = GetClientViewModel(client, 0);

    if (vm0 > 0 && IsValidEntity(vm0))
    {
        SetEntProp(vm0, Prop_Send, "m_nSequence", 0);
    }

    // 调用方(EventPlayerAnim)已递增攻击计数, 作为本次启动的作废标识
    StartCustomAnimSafe(client, sequence, frames, g_iAttackID[client]);
}

// ============================================================================
// 启动自定义动画(带同序列重播保护, 出刀/掏刀共用)
// 引擎对同一 VM 重复设置同一序列号不会重播(cycle 不归零), 上一次动画状态结束
// 前后 VM1 残留同序列时, 再次启动同序列动画会被吞(闲置重置/连续掏刀时出现)。
// 同序列时: 先干净结束动画状态并翻转 VM1 到 idle 清 cycle, 推迟一帧再启动,
// 保证客户端必看到一次序列变化, 强制引擎重启 cycle。
// attackToken: 出刀路径传攻击计数(被更新的出刀作废), 掏刀路径传 0(不作废,
//              改由"攻击动画已在播则放弃"判断保证攻击优先)。
// ============================================================================
void StartCustomAnimSafe(int client, int sequence, int frames, int attackToken)
{
    int vm1 = GetClientViewModel(client, 1);

    if (vm1 <= 0 || !IsValidEntity(vm1))
        return;

    if (GetEntProp(vm1, Prop_Send, "m_nSequence") != sequence)
    {
        Han_SetClientCustomAnim(client, sequence, frames, true, true);
        return;
    }

    Han_StopClientCustomAnim(client);

    vm1 = GetClientViewModel(client, 1);
    if (vm1 > 0 && IsValidEntity(vm1))
    {
        SetEntProp(vm1, Prop_Send, "m_nSequence", 0);
        SetEntPropFloat(vm1, Prop_Data, "m_flCycle", 0.0);
    }

    //PrintToServer("[H-AN] DeltaForceKnife 同序列重播保护触发: %N seq %d", client, sequence);

    DataPack pack = new DataPack();
    pack.WriteCell(client);
    pack.WriteCell(attackToken);
    pack.WriteCell(sequence);
    pack.WriteCell(frames);

    CreateTimer(0.0, Timer_StartAnim, pack, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
}

// 下一帧启动动画(同序列重播保护的后半段)
public Action Timer_StartAnim(Handle timer, DataPack pack)
{
    pack.Reset();

    int client = pack.ReadCell();
    int attackToken = pack.ReadCell();
    int sequence = pack.ReadCell();
    int frames = pack.ReadCell();

    if (client <= 0 ||
        client > MaxClients ||
        !IsClientInGame(client) ||
        !IsPlayerAlive(client))
    {
        return Plugin_Stop;
    }

    // 出刀路径: 期间有更新的出刀则本次启动作废
    if (attackToken != 0 && attackToken != g_iAttackID[client])
    {
        return Plugin_Stop;
    }

    // 掏刀路径: 期间玩家已出刀(攻击动画在播) → 攻击优先, 放弃本次特殊切换
    if (attackToken == 0 && Han_IsClientCustomAnim(client))
    {
        return Plugin_Stop;
    }

    Han_SetClientCustomAnim(client, sequence, frames, true, true);

    return Plugin_Stop;
}

// ============================================================================
// 支持快速近战插件,强制延迟更改攻击动画 用于支持快速近战插件
// 零前摇强制流程(快速近战)的动画启动: 推迟一帧, 落在武器系统 switch-in
// 对齐/镜像写入之后启动自定义动画, 之后每 tick 压制 VM1 压过切换同步
// ============================================================================
public Action Timer_ForcedFlowAnim(Handle timer, DataPack pack)
{
    pack.Reset();

    int client = pack.ReadCell();
    int attackID = pack.ReadCell();
    int idx = pack.ReadCell();
    int sequence = pack.ReadCell();
    int frames = pack.ReadCell();

    if (client <= 0 ||
        client > MaxClients ||
        !IsClientInGame(client) ||
        !IsPlayerAlive(client) ||
        attackID != g_iAttackID[client])
    {
        return Plugin_Stop;
    }

    // 必须仍持有同一把刀(快速近战 0.4 秒窗口内一般不会变)
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon <= 0 || !IsValidEntity(weapon) || GetKnifeIndexByWeapon(weapon) != idx)
    {
        return Plugin_Stop;
    }

    //int vm1 = GetClientViewModel(client, 1);
    //int seqBefore = (vm1 > 0 && IsValidEntity(vm1)) ? GetEntProp(vm1, Prop_Send, "m_nSequence") : -1;

    //PrintToChat(client, "[DFK调试] 快切动画 seq=%d 延迟帧VM1=%d", sequence, seqBefore);

    StartCustomAnimSafe(client, sequence, frames, attackID);

    return Plugin_Stop;
}

// ======================== 攻击事件处理 ========================
public Action EventPlayerAnim(const char[] te_name, const int[] Players, int numClients, float delay)
{
    if (!g_bEnable)
        return Plugin_Continue;

    int player = TE_ReadNum("m_hPlayer");
    int animEvent = TE_ReadNum("m_iEvent");
    int client = MakeCompatEntRef(player);

    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Continue;

    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon <= 0 || !IsValidEntity(weapon))
        return Plugin_Continue;

    int idx = GetKnifeIndexByWeapon(weapon);
    if (idx == -1)
        return Plugin_Continue;

    if (animEvent != 0 && animEvent != 1)
        return Plugin_Continue;

    float now = GetGameTime();

    // 换了刀具组 -> 连招重新从第一刀开始
    if (g_iKnifeIndex[client] != idx)
    {
        g_iLeftPhase[client] = 0;
        g_iRightPhase[client] = 0;
        g_iCurrentAttackPhase[client] = 0;
        g_iKnifeIndex[client] = idx;
    }

    bool wasIdle = (now - g_fLastAttackTime[client] > g_Knives[idx].fIdleTimeout);
    // 空闲超时检查
    if (wasIdle)
    {
        g_iLeftPhase[client] = 0;
        g_iRightPhase[client] = 0;
        g_iCurrentAttackPhase[client] = 0;
    }

    // 零前摇强制流程指纹(外部插件清零 m_flNextAttack 后强制切刀攻击, 如快速近战):
    // 正常攻击时该值为过去/未来的正数, 只有被显式清零才是 0。
    // 响应: 无视 wasIdle 无条件重写间隔重新武装攻击闸门; 动画改为推迟一帧强制自定义动画
    // (落在武器系统 switch-in 对齐/镜像写入之后, 之后每 tick 压制 VM1, 压过切换同步)。
    // 伤害接管/连招段位/音效不受影响。
    bool bForcedFlow = (GetEntPropFloat(client, Prop_Data, "m_flNextAttack") <= 0.0);

    int seq;
    int frames;
    float seqdelay;
    int slot;

    if (animEvent == 0)
    {
        // ===== 右键重击 =====
        slot = 3;
        g_iCurrentAttackPhase[client] = 3;

        int rightPhase = g_iRightPhase[client] % g_Knives[idx].iRightSeqCount;

        seq = g_Knives[idx].iRightSeq[rightPhase];
        frames = g_Knives[idx].iRightFrames;
        // 转刀音效延迟 = 转刀起始帧 ÷ 动画fps, 精确无截断
        seqdelay = float(g_Knives[idx].iRightRotateFrame) / float(g_Knives[idx].iRightFps);

        g_iRightPhase[client] = (rightPhase + 1) % g_Knives[idx].iRightSeqCount;

        if (!wasIdle || bForcedFlow)
        {
            SetEntPropFloat(weapon, Prop_Data, "m_flNextSecondaryAttack", now + g_Knives[idx].fRightInterval);
            SetEntPropFloat(client, Prop_Data, "m_flNextAttack", now + g_Knives[idx].fRightInterval);
        }
    }
    else
    {
        // ===== 左键三连 =====
        int phase = g_iLeftPhase[client];
        slot = phase;
        g_iCurrentAttackPhase[client] = phase;

        seq = g_Knives[idx].iLeftSeq[phase];
        frames = g_Knives[idx].iLeftFrames[phase];
        // 转刀音效延迟 = 转刀起始帧 ÷ 动画fps, 精确无截断
        seqdelay = float(g_Knives[idx].iRotateFrame[phase]) / float(g_Knives[idx].iLeftFps[phase]);

        if (!wasIdle || bForcedFlow)
        {
            SetEntPropFloat(weapon, Prop_Data, "m_flNextPrimaryAttack", now + g_Knives[idx].fLeftInterval[phase]);
            SetEntPropFloat(client, Prop_Data, "m_flNextAttack", now + g_Knives[idx].fLeftInterval[phase]);
        }

        g_iLeftPhase[client] = (phase + 1) % LEFT_COMBO_COUNT;
    }

    g_fLastAttackTime[client] = now;

    g_iAttackID[client]++;
    int attackID = g_iAttackID[client];

    StopKnifeSounds(client, idx);

    if (!bForcedFlow)
    {
        ForceAttackAnimation(client, seq, frames);
    }
    else
    {
        // 零前摇强制流程(快速近战): 推迟一帧再启动自定义动画,
        // 落在武器系统 switch-in 对齐/镜像写入之后, 由自定义动画模块每 tick 压制 VM1
        DataPack pack2 = new DataPack();
        pack2.WriteCell(client);
        pack2.WriteCell(attackID);
        pack2.WriteCell(idx);
        pack2.WriteCell(seq);
        pack2.WriteCell(frames);

        CreateTimer(0.0, Timer_ForcedFlowAnim, pack2, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
    }

    DataPack pack = new DataPack();
    pack.WriteCell(client);
    pack.WriteCell(attackID);
    pack.WriteCell(idx);
    pack.WriteCell(slot);

    CreateTimer(seqdelay, Timer_DelaySound, pack, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);

    return Plugin_Continue;
}

public Action Timer_DelaySound(Handle timer, DataPack pack)
{
    pack.Reset();

    int client = pack.ReadCell();
    int attackID = pack.ReadCell();
    int idx = pack.ReadCell();
    int slot = pack.ReadCell();

    // 这个 Timer 属于旧攻击 / 音效开关已关
    if (client <= 0 ||
        client > MaxClients ||
        !IsClientInGame(client) ||
        !IsPlayerAlive(client) ||
        attackID != g_iAttackID[client] ||
        idx < 0 ||
        idx >= g_iKnifeCount ||
        !g_bSoundEnable)
    {
        return Plugin_Stop;
    }

    char sSoundPath[PLATFORM_MAX_PATH];

    switch (slot)
    {
        case 0:
        {
            strcopy(sSoundPath, sizeof(sSoundPath), g_Knives[idx].sRotateSound1);
        }

        case 1:
        {
            strcopy(sSoundPath, sizeof(sSoundPath), g_Knives[idx].sRotateSound2);
        }

        case 2:
        {
            strcopy(sSoundPath, sizeof(sSoundPath), g_Knives[idx].sRotateSound3);
        }

        case 3:
        {
            strcopy(sSoundPath, sizeof(sSoundPath), g_Knives[idx].sRightRotateSound);
        }

        default:
        {
            return Plugin_Stop;
        }
    }

    // 音效留空 = 不播放
    if (strlen(sSoundPath) == 0)
        return Plugin_Stop;

    EmitSoundToAll(sSoundPath, client, SNDCHAN_KNIFE, SNDLEVEL_NORMAL);

    return Plugin_Stop;
}

// ======================== 命中/击杀音效 ========================
public Action EventPlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bSoundEnable)
        return Plugin_Continue;

    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    if (attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker) || !IsPlayerAlive(attacker))
        return Plugin_Continue;

    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (victim <= 0 || victim > MaxClients || !IsClientInGame(victim) || !IsPlayerAlive(victim))
       return Plugin_Continue;

    if (attacker == victim)
        return Plugin_Continue;

    int weapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
    if (weapon <= 0 || !IsValidEntity(weapon))
        return Plugin_Continue;

    int idx = GetKnifeIndexByWeapon(weapon);
    if (idx == -1)
        return Plugin_Continue;

    float pos[3], ang[3];
    GetClientEyePosition(attacker, pos);
    GetClientEyeAngles(attacker, ang);

    TR_TraceRayFilter(pos, ang, MASK_SHOT, RayType_Infinite, Trace_HitVictimOnly, victim);

    int Hitgroup = TR_GetHitGroup();

    SetEventInt(event, "hitgroup", Hitgroup);

    // 保存这一次攻击的命中部位(击杀音判断用)
    g_iLastKnifeHitGroup[victim][attacker] = Hitgroup;

    // 命中音留空 = 不播放
    if (strlen(g_Knives[idx].sHitSound) > 0)
    {
        EmitSoundToClient(attacker, g_Knives[idx].sHitSound);
    }

    return Plugin_Continue;
}

public Action EventPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bSoundEnable)
        return Plugin_Continue;

    int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
    if (attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker) || !IsPlayerAlive(attacker))
        return Plugin_Continue;

    int victim = GetClientOfUserId(GetEventInt(event, "userid"));
    if (attacker == victim)
        return Plugin_Continue;

    int weapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
    if (weapon <= 0 || !IsValidEntity(weapon))
        return Plugin_Continue;

    int idx = GetKnifeIndexByWeapon(weapon);
    if (idx == -1)
        return Plugin_Continue;

    char WeaponName[50];
    GetEventString(event, "weapon", WeaponName, sizeof(WeaponName));

    char eventWeaponClass[64];
    Format(eventWeaponClass, sizeof(eventWeaponClass), "weapon_%s", WeaponName);

    if (!StrEqual(eventWeaponClass, g_Knives[idx].sClassName, false))
        return Plugin_Continue;

    int hitgroup = g_iLastKnifeHitGroup[victim][attacker];

    // 爆头击杀音(命中部位 0/1), 留空不播
    if ((hitgroup == 0 || hitgroup == 1) && strlen(g_Knives[idx].sHeadshotSound) > 0)
    {
        EmitSoundToClient(attacker, g_Knives[idx].sHeadshotSound);
    }
    else if (hitgroup != 0 && hitgroup != 1 && strlen(g_Knives[idx].sKillSound) > 0)
    {
        EmitSoundToClient(attacker, g_Knives[idx].sKillSound);
    }

    return Plugin_Continue;
}

public void EventPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0)
        return;

    ResetPlayerState(client);
}

// ======================== 射线过滤 ========================
public bool Trace_HitVictimOnly(int entity, int contentsMask, any victim)
{
    return entity == victim;
}

// ======================== 配置读取 ========================
void LoadConfig()
{
    g_iKnifeCount = 0;

    if (g_hClassMap != null)
        delete g_hClassMap;
    g_hClassMap = new StringMap();

    char cfgPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, cfgPath, sizeof(cfgPath), "configs/DeltaForceKnife.cfg");

    if (!FileExists(cfgPath))
        WriteDefaultConfig(cfgPath);

    Handle kv = CreateKeyValues("DeltaForceKnife");

    if (!FileToKeyValues(kv, cfgPath))
    {
        CloseHandle(kv);
        LogError("[H-AN] DeltaForceKnife 配置文件读取失败: %s", cfgPath);
        return;
    }

    char groupName[64];

    if (KvGotoFirstSubKey(kv))
    {
        do
        {
            if (g_iKnifeCount >= MAX_DFKNIVES)
            {
                LogError("[H-AN] DeltaForceKnife 组数量已达上限 %d, 忽略其余组", MAX_DFKNIVES);
                break;
            }

            KvGetSectionName(kv, groupName, sizeof(groupName));
            LoadKnifeGroup(kv, groupName);
        }
        while (KvGotoNextKey(kv));
    }

    CloseHandle(kv);

    PrintToServer("[H-AN] DeltaForceKnife 已加载 %d 组三角洲刀具", g_iKnifeCount);
}

void LoadKnifeGroup(Handle kv, const char[] groupName)
{
    char sClassName[64];
    KvGetString(kv, "ClassName", sClassName, sizeof(sClassName), "");

    if (strlen(sClassName) == 0)
    {
        LogError("[H-AN] DeltaForceKnife 组 [%s] 缺少 ClassName, 已跳过", groupName);
        return;
    }

    // 默认值 = 北极星布局: 新组只填 ClassName 也能直接按北极星逻辑驱动
    static const int sDefaultLeftSeq[LEFT_COMBO_COUNT] = {4, 5, 6};
    static const int sDefaultLeftFrames[LEFT_COMBO_COUNT] = {40, 60, 61};
    static const float sDefaultLeftInterval[LEFT_COMBO_COUNT] = {0.3, 0.4, 0.6};
    static const float sDefaultLeftDamage[LEFT_COMBO_COUNT] = {30.0, 30.0, 42.0};

    int idx = g_iKnifeCount;

    // classname 统一小写作为查表键
    StringToLower(sClassName, sClassName, sizeof(sClassName));
    strcopy(g_Knives[idx].sClassName, 64, sClassName);

    g_Knives[idx].fIdleTimeout = KvGetFloat(kv, "IdleTimeout", 2.0);

    char key[32];
    for (int i = 0; i < LEFT_COMBO_COUNT; i++)
    {
        Format(key, sizeof(key), "LeftSequence%d", i + 1);
        g_Knives[idx].iLeftSeq[i] = KvGetNum(kv, key, sDefaultLeftSeq[i]);

        Format(key, sizeof(key), "LeftFrames%d", i + 1);
        g_Knives[idx].iLeftFrames[i] = KvGetNum(kv, key, sDefaultLeftFrames[i]);

        Format(key, sizeof(key), "LeftFps%d", i + 1);
        g_Knives[idx].iLeftFps[i] = KvGetNum(kv, key, 66);
        if (g_Knives[idx].iLeftFps[i] <= 0)
            g_Knives[idx].iLeftFps[i] = 66;

        // 间隔键含义(与北极星配置注释一致): Interval1=三->一, Interval2=一->二, Interval3=二->三
        // 存放为"该刀之后到下一刀"的间隔: [0]=一->二取Interval2, [1]=二->三取Interval3, [2]=三->一取Interval1
        Format(key, sizeof(key), "LeftInterval%d", (i + 1) % LEFT_COMBO_COUNT + 1);
        g_Knives[idx].fLeftInterval[i] = KvGetFloat(kv, key, sDefaultLeftInterval[i]);

        Format(key, sizeof(key), "LeftDamage%d", i + 1);
        g_Knives[idx].fLeftDamage[i] = KvGetFloat(kv, key, sDefaultLeftDamage[i]);
    }

    // 右键序列列表: 1个=固定动画, 多个=逗号分隔交替循环(如 "8,6")
    char sRightSeq[64];
    KvGetString(kv, "RightSequence", sRightSeq, sizeof(sRightSeq), "8,6");

    char sParts[MAX_RIGHT_SEQ][16];
    int count = ExplodeString(sRightSeq, ",", sParts, MAX_RIGHT_SEQ, 16);

    g_Knives[idx].iRightSeqCount = 0;
    for (int i = 0; i < count; i++)
    {
        TrimString(sParts[i]);
        if (strlen(sParts[i]) == 0)
            continue;

        g_Knives[idx].iRightSeq[g_Knives[idx].iRightSeqCount] = StringToInt(sParts[i]);
        g_Knives[idx].iRightSeqCount++;
    }

    if (g_Knives[idx].iRightSeqCount == 0)
    {
        LogError("[H-AN] DeltaForceKnife 组 [%s] RightSequence 无效, 已跳过", groupName);
        return;
    }

    g_Knives[idx].iRightFrames = KvGetNum(kv, "RightFrames", 61);
    g_Knives[idx].iRightFps = KvGetNum(kv, "RightFps", 66);
    if (g_Knives[idx].iRightFps <= 0)
        g_Knives[idx].iRightFps = 66;
    g_Knives[idx].fRightInterval = KvGetFloat(kv, "RightInterval", 0.6);
    g_Knives[idx].fRightDamage = KvGetFloat(kv, "RightDamage", 60.0);
    g_Knives[idx].fHeadshotMultiplier = KvGetFloat(kv, "HeadshotMultiplier", 2.0);

    // 转刀音效: "帧号:路径" = 动画第N帧开始播放; "路径"(无冒号) = 第0帧立即播放; 留空 = 不播放
    char sSoundValue[PLATFORM_MAX_PATH];
    char sSoundPath[PLATFORM_MAX_PATH];

    KvGetString(kv, "RotateSound1", sSoundValue, sizeof(sSoundValue), "");
    ParseRotateSoundValue(sSoundValue, g_Knives[idx].iRotateFrame[0], sSoundPath, sizeof(sSoundPath));
    strcopy(g_Knives[idx].sRotateSound1, PLATFORM_MAX_PATH, sSoundPath);

    KvGetString(kv, "RotateSound2", sSoundValue, sizeof(sSoundValue), "");
    ParseRotateSoundValue(sSoundValue, g_Knives[idx].iRotateFrame[1], sSoundPath, sizeof(sSoundPath));
    strcopy(g_Knives[idx].sRotateSound2, PLATFORM_MAX_PATH, sSoundPath);

    KvGetString(kv, "RotateSound3", sSoundValue, sizeof(sSoundValue), "");
    ParseRotateSoundValue(sSoundValue, g_Knives[idx].iRotateFrame[2], sSoundPath, sizeof(sSoundPath));
    strcopy(g_Knives[idx].sRotateSound3, PLATFORM_MAX_PATH, sSoundPath);

    KvGetString(kv, "RightRotateSound", sSoundValue, sizeof(sSoundValue), "");
    ParseRotateSoundValue(sSoundValue, g_Knives[idx].iRightRotateFrame, sSoundPath, sizeof(sSoundPath));
    strcopy(g_Knives[idx].sRightRotateSound, PLATFORM_MAX_PATH, sSoundPath);

    // 双切换动画(可选): 不填 DrawSequence2 = 功能关闭, 掏刀行为与现在完全一致
    g_Knives[idx].iDrawSeq2 = -1;
    g_Knives[idx].iDrawFrames2 = 0;

    int drawSeq2 = KvGetNum(kv, "DrawSequence2", -1);
    if (drawSeq2 >= 0)
    {
        int drawFrames2 = KvGetNum(kv, "DrawFrames2", -1);
        if (drawFrames2 <= 0)
        {
            LogError("[H-AN] DeltaForceKnife 组 [%s] 填了 DrawSequence2 但缺少有效 DrawFrames2, 双切换未启用", groupName);
        }
        else
        {
            g_Knives[idx].iDrawSeq2 = drawSeq2;
            g_Knives[idx].iDrawFrames2 = drawFrames2;
        }
    }

    KvGetString(kv, "DrawSound1", g_Knives[idx].sDrawSound1, PLATFORM_MAX_PATH, "");
    KvGetString(kv, "DrawSound2", g_Knives[idx].sDrawSound2, PLATFORM_MAX_PATH, "");

    KvGetString(kv, "HitSound", g_Knives[idx].sHitSound, PLATFORM_MAX_PATH, "");
    KvGetString(kv, "KillSound", g_Knives[idx].sKillSound, PLATFORM_MAX_PATH, "");
    KvGetString(kv, "HeadshotSound", g_Knives[idx].sHeadshotSound, PLATFORM_MAX_PATH, "");

    g_hClassMap.SetValue(sClassName, idx);
    g_iKnifeCount++;

    PrintToServer("[H-AN] DeltaForceKnife 组 [%s] -> %s", groupName, sClassName);
}

// ============================================================================
// 解析转刀音效值: "帧号:路径" = 动画第N帧开始播放
//                 "路径"(无冒号)  = 第0帧立即播放
// ============================================================================
void ParseRotateSoundValue(const char[] value, int &frame, char[] path, int pathLen)
{
    char sFrame[16];

    // SplitString: sFrame = 冒号前部分, 返回值 = 冒号后起始下标(-1 = 无冒号)
    int pos = SplitString(value, ":", sFrame, sizeof(sFrame));
    if (pos == -1)
    {
        // 无冒号 = 纯路径, 第0帧立即播放
        frame = 0;
        strcopy(path, pathLen, value);
        return;
    }

    frame = StringToInt(sFrame);
    if (frame < 0)
        frame = 0;

    // 冒号之后的部分即路径
    int i = 0;
    while (value[pos + i] != '\0' && i < pathLen - 1)
    {
        path[i] = value[pos + i];
        i++;
    }
    path[i] = '\0';
}

// ============================================================
// 生成默认配置(首刷自动生成, 内容 = 北极星组模板)
// ============================================================
void WriteDefaultConfig(const char[] path)
{
    Handle file = OpenFile(path, "w");
    if (file == INVALID_HANDLE)
        return;

    // ============================================================
    // 配置说明
    // ============================================================
    WriteFileLine(file, "// ============================================================");
    WriteFileLine(file, "// DeltaForceKnife 三角洲风格刀具通用驱动配置");
    WriteFileLine(file, "// 每把刀 = 一个组, 组名随意(建议用武器短名), 只有填写进组的武器会被驱动");
    WriteFileLine(file, "// 修改配置后换图生效, 或用 sm_deltaforce_knife_reload 立即重载");
    WriteFileLine(file, "// ============================================================");
    WriteFileLine(file, "// ClassName              武器实体名称");
    WriteFileLine(file, "// IdleTimeout            连续攻击间隔超过此时间后, 左键连招重新从第一刀开始");
    WriteFileLine(file, "//");
    WriteFileLine(file, "// LeftSequence1~3        左键三刀的 QC 动画序列号");
    WriteFileLine(file, "// LeftFrames1~3          左键三刀的动画总帧数(传给武器系统, 动画持续时长 = 帧数/30 秒, 不参与音效计算)");
    WriteFileLine(file, "// LeftFps1~3             左键三刀动画的 fps, 转刀音效帧号换算用(不填默认 66)");
    WriteFileLine(file, "// LeftInterval1          左键 第三刀 -> 第一刀 的攻击间隔");
    WriteFileLine(file, "// LeftInterval2          左键 第一刀 -> 第二刀 的攻击间隔");
    WriteFileLine(file, "// LeftInterval3          左键 第二刀 -> 第三刀 的攻击间隔");
    WriteFileLine(file, "// LeftDamage1~3          左键三刀基础伤害");
    WriteFileLine(file, "//");
    WriteFileLine(file, "// RightSequence          右键 QC 动画序列号, 逗号分隔: 填1个=固定动画, 填多个=按顺序交替循环(如 \"8,6\")");
    WriteFileLine(file, "// RightFrames            右键动画总帧数(传给武器系统, 不参与音效计算)");
    WriteFileLine(file, "// RightFps               右键动画 fps(不填默认 66)");
    WriteFileLine(file, "// RightInterval          右键 -> 下一次右键 的攻击间隔");
    WriteFileLine(file, "// RightDamage            右键基础伤害");
    WriteFileLine(file, "//");
    WriteFileLine(file, "// HeadshotMultiplier     爆头伤害倍率");
    WriteFileLine(file, "//");
    WriteFileLine(file, "// RotateSound1~3         左键各刀转刀音效, 格式 \"帧号:路径\" = 动画第N帧开始播放(不带帧号 = 第0帧立即播放, 留空 = 不播放)");
    WriteFileLine(file, "// RightRotateSound       右键转刀音效, 格式同 RotateSound1~3");
    WriteFileLine(file, "//");
    WriteFileLine(file, "// DrawSequence2          特殊切换的 QC 序列号(填了才启用双切换动画: 50% 播此序列, 50% 走原版同步 draw)");
    WriteFileLine(file, "// DrawFrames2            特殊切换动画总帧数(状态时长 = 帧数/30, 必须覆盖整个切换动画)");
    WriteFileLine(file, "// DrawSound1             普通切换音效(走同步 draw 时播放, 留空 = 不播放)");
    WriteFileLine(file, "// DrawSound2             特殊切换音效(走特殊 draw 时播放, 留空 = 不播放)");
    WriteFileLine(file, "// 注意: 启用双切换时, 该武器在武器系统配置内的 switchsound 必须留空, 否则会叠加播放固定切换音效");
    WriteFileLine(file, "// HitSound               普通命中音效(留空 = 不播放)");
    WriteFileLine(file, "// KillSound              普通击杀音效(留空 = 不播放)");
    WriteFileLine(file, "// HeadshotSound          爆头击杀音效(留空 = 不播放)");
    WriteFileLine(file, "//");
    WriteFileLine(file, "// 注意: 组内不填的键会使用北极星默认值(左键 4/5/6, 右键 8,6 交替)");
    WriteFileLine(file, "// ============================================================");
    WriteFileLine(file, "");

    // ============================================================
    // 配置
    // ============================================================
    WriteFileLine(file, "\"DeltaForceKnife\"");
    WriteFileLine(file, "{");

    // ------------------------------------------------------------
    // 北极星(默认组, 数值与线上北极星插件行为一致)
    // ------------------------------------------------------------
    WriteFileLine(file, "    // ==================== 北极星 ====================");
    WriteFileLine(file, "    \"beijixing\"");
    WriteFileLine(file, "    {");

    WriteFileLine(file, "        // 武器实体名称");
    WriteFileLine(file, "        \"ClassName\"              \"weapon_beijixing\"");

    WriteFileLine(file, "        // 连招空闲超时");
    WriteFileLine(file, "        \"IdleTimeout\"            \"2.0\"");

    WriteFileLine(file, "        // 左键三刀 QC 序列号");
    WriteFileLine(file, "        \"LeftSequence1\"          \"4\"");
    WriteFileLine(file, "        \"LeftSequence2\"          \"5\"");
    WriteFileLine(file, "        \"LeftSequence3\"          \"6\"");

    WriteFileLine(file, "        // 左键三刀动画总帧数(只管动画时长, 不参与音效)");
    WriteFileLine(file, "        \"LeftFrames1\"            \"40\"");
    WriteFileLine(file, "        \"LeftFrames2\"            \"60\"");
    WriteFileLine(file, "        \"LeftFrames3\"            \"61\"");
    WriteFileLine(file, "        // 左键三刀动画 fps(转刀音效帧号换算用, 不填默认 66)");
    WriteFileLine(file, "        // \"LeftFps1\"              \"66\"");
    WriteFileLine(file, "        // \"LeftFps2\"              \"66\"");
    WriteFileLine(file, "        // \"LeftFps3\"              \"66\"");

    WriteFileLine(file, "        // 左键攻击间隔");
    WriteFileLine(file, "        \"LeftInterval1\"          \"0.6\"    // 第三刀 -> 第一刀");
    WriteFileLine(file, "        \"LeftInterval2\"          \"0.3\"    // 第一刀 -> 第二刀");
    WriteFileLine(file, "        \"LeftInterval3\"          \"0.4\"    // 第二刀 -> 第三刀");

    WriteFileLine(file, "        // 左键伤害");
    WriteFileLine(file, "        \"LeftDamage1\"            \"30.0\"    // 第一刀");
    WriteFileLine(file, "        \"LeftDamage2\"            \"30.0\"    // 第二刀");
    WriteFileLine(file, "        \"LeftDamage3\"            \"42.0\"    // 第三刀");

    WriteFileLine(file, "        // 右键: 先 8 后 6 交替(只填一个则为固定动画)");
    WriteFileLine(file, "        \"RightSequence\"          \"8,6\"");
    WriteFileLine(file, "        \"RightFrames\"            \"61\"");
    WriteFileLine(file, "        // \"RightFps\"              \"66\"");
    WriteFileLine(file, "        \"RightInterval\"          \"0.6\"");
    WriteFileLine(file, "        \"RightDamage\"            \"60.0\"");

    WriteFileLine(file, "        // 爆头伤害倍率");
    WriteFileLine(file, "        \"HeadshotMultiplier\"     \"2.0\"");

    WriteFileLine(file, "        // 转刀音效: \"帧号:路径\" = 动画第N帧开始播放(不带帧号 = 第0帧立即播放)");
    WriteFileLine(file, "        \"RotateSound1\"           \"40:weapons/beijixing/beijixing_rotate_1.wav\"");
    WriteFileLine(file, "        \"RotateSound2\"           \"60:weapons/beijixing/beijixing_rotate_2.wav\"");
    WriteFileLine(file, "        \"RotateSound3\"           \"61:weapons/beijixing/beijixing_rotate_3.wav\"");
    WriteFileLine(file, "        \"RightRotateSound\"       \"61:weapons/beijixing/beijixing_rotate_3.wav\"");

    WriteFileLine(file, "        // 命中/击杀音效");
    WriteFileLine(file, "        \"HitSound\"               \"weapons/beijixing/hit.wav\"");
    WriteFileLine(file, "        \"KillSound\"              \"weapons/beijixing/kill.wav\"");
    WriteFileLine(file, "        \"HeadshotSound\"          \"weapons/beijixing/headshot.wav\"");

    WriteFileLine(file, "    }");

    // ------------------------------------------------------------
    // 新刀具模板(复制一份, 去掉每行开头的 // 注释, 改组名和参数即可)
    // ------------------------------------------------------------
    WriteFileLine(file, "");
    WriteFileLine(file, "    // ==================== 新刀具模板(复制一份去掉注释使用) ====================");
    WriteFileLine(file, "    // \"my_new_knife\"");
    WriteFileLine(file, "    // {");
    WriteFileLine(file, "    //     \"ClassName\"              \"weapon_mynewknife\"");
    WriteFileLine(file, "    //     \"IdleTimeout\"            \"2.0\"");
    WriteFileLine(file, "    //     \"LeftSequence1\"          \"4\"");
    WriteFileLine(file, "    //     \"LeftSequence2\"          \"5\"");
    WriteFileLine(file, "    //     \"LeftSequence3\"          \"6\"");
    WriteFileLine(file, "    //     \"LeftFrames1\"            \"40\"     // 动画总帧数(只管动画时长)");
    WriteFileLine(file, "    //     \"LeftFrames2\"            \"60\"");
    WriteFileLine(file, "    //     \"LeftFrames3\"            \"61\"");
    WriteFileLine(file, "    //     \"LeftFps1\"               \"64\"     // 动画fps(转刀音效帧号换算, 不填默认66)");
    WriteFileLine(file, "    //     \"LeftFps2\"               \"71\"");
    WriteFileLine(file, "    //     \"LeftFps3\"               \"64\"");
    WriteFileLine(file, "    //     \"LeftInterval1\"          \"0.6\"    // 第三刀 -> 第一刀");
    WriteFileLine(file, "    //     \"LeftInterval2\"          \"0.3\"    // 第一刀 -> 第二刀");
    WriteFileLine(file, "    //     \"LeftInterval3\"          \"0.4\"    // 第二刀 -> 第三刀");
    WriteFileLine(file, "    //     \"LeftDamage1\"            \"30.0\"");
    WriteFileLine(file, "    //     \"LeftDamage2\"            \"30.0\"");
    WriteFileLine(file, "    //     \"LeftDamage3\"            \"42.0\"");
    WriteFileLine(file, "    //     \"RightSequence\"          \"8\"");
    WriteFileLine(file, "    //     \"RightFrames\"            \"61\"     // 动画总帧数");
    WriteFileLine(file, "    //     \"RightFps\"               \"64\"     // 不填默认66");
    WriteFileLine(file, "    //     \"RightInterval\"          \"0.6\"");
    WriteFileLine(file, "    //     \"RightDamage\"            \"60.0\"");
    WriteFileLine(file, "    //     \"HeadshotMultiplier\"     \"2.0\"");
    WriteFileLine(file, "    //     \"RotateSound1\"           \"40:weapons/mynewknife/rotate_1.wav\"   // 动画第40帧开始播放");
    WriteFileLine(file, "    //     \"RotateSound2\"           \"40:weapons/mynewknife/rotate_2.wav\"");
    WriteFileLine(file, "    //     \"RotateSound3\"           \"55:weapons/mynewknife/rotate_3.wav\"");
    WriteFileLine(file, "    //     \"RightRotateSound\"       \"40:weapons/mynewknife/rotate_3.wav\"");
    WriteFileLine(file, "    //     \"DrawSequence2\"          \"12\"     // 特殊切换序列号(填了才启用双切换)");
    WriteFileLine(file, "    //     \"DrawFrames2\"            \"80\"     // 特殊切换动画总帧数");
    WriteFileLine(file, "    //     \"DrawSound1\"             \"weapons/mynewknife/draw_normal.wav\"");
    WriteFileLine(file, "    //     \"DrawSound2\"             \"weapons/mynewknife/draw_special.wav\"");
    WriteFileLine(file, "    //     \"HitSound\"               \"weapons/mynewknife/hit.wav\"");
    WriteFileLine(file, "    //     \"KillSound\"              \"weapons/mynewknife/kill.wav\"");
    WriteFileLine(file, "    //     \"HeadshotSound\"          \"weapons/mynewknife/headshot.wav\"");
    WriteFileLine(file, "    // }");

    WriteFileLine(file, "}");

    CloseHandle(file);
}

// ======================== 音效预缓存 ========================
void PrecacheSounds()
{
    for (int i = 0; i < g_iKnifeCount; i++)
    {
        PrecacheSoundPath(g_Knives[i].sRotateSound1);
        PrecacheSoundPath(g_Knives[i].sRotateSound2);
        PrecacheSoundPath(g_Knives[i].sRotateSound3);
        PrecacheSoundPath(g_Knives[i].sRightRotateSound);
        PrecacheSoundPath(g_Knives[i].sDrawSound1);
        PrecacheSoundPath(g_Knives[i].sDrawSound2);
        PrecacheSoundPath(g_Knives[i].sHitSound);
        PrecacheSoundPath(g_Knives[i].sKillSound);
        PrecacheSoundPath(g_Knives[i].sHeadshotSound);
    }
}

void PrecacheSoundPath(const char[] path)
{
    if (strlen(path) > 0)
        PrecacheSound(path);
}

// ======================== 工具函数 ========================
int GetKnifeIndexByWeapon(int weapon)
{
    char cls[64];
    GetEntityClassname(weapon, cls, sizeof(cls));
    StringToLower(cls, cls, sizeof(cls));

    int idx = -1;
    if (g_hClassMap != null && g_hClassMap.GetValue(cls, idx))
        return idx;

    return -1;
}

void StringToLower(const char[] src, char[] dest, int maxlen)
{
    strcopy(dest, maxlen, src);

    for (int i = 0; i < maxlen && dest[i] != '\0'; i++)
    {
        dest[i] = CharToLower(dest[i]);
    }
}

// ======================== 管理命令 ========================
public Action CmdReload(int client, int args)
{
    LoadConfig();
    PrecacheSounds();

    // 重载后组索引可能变化, 重置所有玩家的连招状态
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
            ResetPlayerState(i);
    }

    ReplyToCommand(client, "[H-AN] DeltaForceKnife 配置已重载, 当前 %d 组", g_iKnifeCount);
    return Plugin_Handled;
}

// ============================================================
// 创建 CVar (只有总开关和音效开关, 组参数全部走 cfg)
// ============================================================

void CreateDeltaKnifeCVars()
{
    g_hEnableCvar = CreateConVar("sm_deltaforce_knife_enable", "1", "三角洲刀具通用驱动总开关");
    g_hSoundEnableCvar = CreateConVar("sm_deltaforce_knife_sound_enable", "1", "音效总开关(旋转音/命中音/击杀音)");

    g_hEnableCvar.AddChangeHook(OnDeltaKnifeCvarChanged);
    g_hSoundEnableCvar.AddChangeHook(OnDeltaKnifeCvarChanged);

    RefreshDeltaKnifeCVars();
}

public void OnDeltaKnifeCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    RefreshDeltaKnifeCVars();
}


void RefreshDeltaKnifeCVars()
{
    g_bEnable = g_hEnableCvar.BoolValue;
    g_bSoundEnable = g_hSoundEnableCvar.BoolValue;
}

// ============================================================================================
// 强制改写覆盖快速近战的视图模型硬编码隐藏, 以便刀具动画和音效正常播放, 用于支持快速近战插件
// ============================================================================================

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Continue;

    int ActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (ActiveWeapon <= 0 || !IsValidEntity(ActiveWeapon))
        return Plugin_Continue;

    int vm0 = GetClientViewModel(client, 0);
    if (vm0 <= 0 || !IsValidEntity(vm0))
        return Plugin_Continue;

    int vm1 = GetClientViewModel(client, 1);
    if (vm1 <= 0 || !IsValidEntity(vm1))
        return Plugin_Continue;

    int vm0Effects = GetEntProp(vm0, Prop_Send, "m_fEffects");
    int vm1Effects = GetEntProp(vm1, Prop_Send, "m_fEffects");

    int idx = GetKnifeIndexByWeapon(ActiveWeapon);
    if ( buttons & IN_ATTACK || buttons & IN_ATTACK2 )
    {
        if(idx != -1)
        {
            vm1Effects &= ~EF_NODRAW;
            SetEntProp(vm1, Prop_Send, "m_fEffects", vm1Effects);

            vm0Effects |= EF_NODRAW;
            SetEntProp(vm0, Prop_Send, "m_fEffects", vm0Effects);
        }
        else
        {
            if(vm0Effects != EF_NODRAW )
            {  
                char ClassName[30];
                GetEntityClassname(ActiveWeapon, ClassName, sizeof(ClassName));
                if(StrEqual(ClassName, "weapon_knife", false) && g_hOldWeaponFix != null && !g_hOldWeaponFix.BoolValue)
                    return Plugin_Continue;

                vm1Effects &= ~EF_NODRAW;
                SetEntProp(vm1, Prop_Send, "m_fEffects", vm1Effects);
                vm0Effects |= EF_NODRAW;
                SetEntProp(vm0, Prop_Send, "m_fEffects", vm0Effects);
                
            }
        }


    }

    return Plugin_Continue;
}
