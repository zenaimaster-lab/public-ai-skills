---
name: mt5-dashboard-buttons
description: "CRITICAL: Fix unreliable CButton clicks in MQL5 CAppDialog dashboards. MUST use direct CHARTEVENT_OBJECT_CLICK interception with OBJPROP_STATE guard — never rely on CAppDialog's internal event routing for buttons."
---

# MQL5 CAppDialog Button Click Fix

## WHEN TO USE
Use this skill for **ANY** MQL5 Expert Advisor that uses `CAppDialog` with `CButton` controls. This is **MANDATORY** — CAppDialog's internal event routing silently swallows button clicks.

## THE PROBLEM

`CAppDialog` uses `OBJ_BUTTON` (toggle buttons) internally. Its event routing chain has multiple failure points:

```
CHARTEVENT_OBJECT_CLICK → CAppDialog::ChartEvent → CWndContainer::OnEvent
→ iterate children → CButton::OnEvent → EVENT_MAP → handler
```

**Symptoms:**
- Buttons require 3-10 clicks to register
- Click behavior is random/inconsistent
- Some buttons work, others don't
- Problem worsens when OnTimer/OnTick update UI labels frequently
- **ON/OFF buttons flash momentarily then revert to original state** (double-toggle bug)

**Root causes (ALL contribute):**
1. `OBJ_BUTTON` is a toggle — state flips true↔false, CAppDialog may only dispatch on one direction
2. `CHARTEVENT_OBJECT_CHANGE` fires on every programmatic label update (OnTimer), flooding the event queue
3. All controls sharing same `OBJPROP_ZORDER` causes MT5 to randomly pick click targets
4. CAppDialog's internal child iteration can silently consume click events
5. **`ObjectSetInteger(OBJPROP_STATE, false)` generates a secondary event that re-triggers HandleDirectClick → handler fires TWICE → double-toggle → button reverts**

## THE FIX (5 layers — ALL required)

### Layer 1: Direct Click Interception (THE KEY FIX)

Bypass CAppDialog's event routing entirely. Handle `CHARTEVENT_OBJECT_CLICK` BEFORE passing to `CAppDialog::ChartEvent`:

**In Dashboard.mqh — add public method:**
```cpp
// Public method — bypasses CAppDialog event routing
bool CDashboard::HandleDirectClick(const string &objName)
{
   // ⚠️ LAYER 5: OBJPROP_STATE guard — MUST be first!
   // Without this, resetting STATE below generates a secondary event,
   // re-triggering this function → handler fires TWICE → double-toggle → revert
   if(ObjectGetInteger(m_chart_id, objName, OBJPROP_STATE) == 0)
      return false;
   
   // Reset OBJ_BUTTON toggle state immediately
   ObjectSetInteger(m_chart_id, objName, OBJPROP_STATE, false);
   
   // Match against every button and call handler directly
   if(objName == m_btnAutoTrade.Name()) { OnAutoT(); return true; }
   if(objName == m_btnDayPicker.Name()) { OnDayPicker(); return true; }
   // ... ALL buttons listed here
   return false;
}
```

**In main .mq5 — intercept BEFORE CAppDialog:**
```cpp
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // FIRST: Direct button click handling — bypasses CAppDialog
   // ⚠️ Do NOT return early after HandleDirectClick — command queue must still run!
   bool handled = false;
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(g_dashboard.HandleDirectClick(sparam))
      {
         handled = true;
         ChartRedraw();
      }
   }
   
   // THEN: Pass non-handled events to CAppDialog (skip CHART_CHANGE, OBJECT_CHANGE, and handled clicks)
   if(!handled && id != CHARTEVENT_CHART_CHANGE && id != CHARTEVENT_OBJECT_CHANGE)
      g_dashboard.ChartEvent(id, lparam, dparam, sparam);
   
   // Only mark dirty on ENDEDIT, NOT OBJECT_CHANGE
   if(id == CHARTEVENT_OBJECT_ENDEDIT)
      g_dashboard.MarkDirtyPublic();
   
   // Command queue dispatcher runs ALWAYS (never behind early return!)
   while(g_dashboard.HasCommand())
   {
      ENUM_DASHBOARD_CMD cmd = g_dashboard.PopCommand();
      // ... process commands
   }
}
```

> **⚠️ CRITICAL: Do NOT use `return;` after HandleDirectClick!**
> Early return skips the command queue dispatcher. Any button handler that calls `PushCmd()` (FLATTEN, PLACE STOP, BUY/SELL MKT, LOCK, REVERSE, etc.) will have its command silently dropped. Use a `bool handled` flag instead.

### Layer 2: Layered ZORDER

Different ZORDER values for different control types:

```cpp
// Labels (non-interactive) — lowest
void CtrlShow(CWnd &obj) {
   obj.Show();
   ObjectSetInteger(m_chart_id, obj.Name(), OBJPROP_ZORDER, 10);
}

// Edit fields (need focus clicks) — middle  
void CtrlShowEdit(CWnd &obj) {
   obj.Show();
   ObjectSetInteger(m_chart_id, obj.Name(), OBJPROP_ZORDER, 50);
}

// Buttons (must always win clicks) — highest
void CtrlShowBtn(CWnd &obj) {
   obj.Show();
   ObjectSetInteger(m_chart_id, obj.Name(), OBJPROP_ZORDER, 200);
}

// Hidden controls — negative (prevent ghost clicks)
void CtrlHide(CWnd &obj) {
   obj.Hide();
   ObjectSetInteger(m_chart_id, obj.Name(), OBJPROP_ZORDER, -100);
}
```

In `MB()` (button creator), set ZORDER=200:
```cpp
Add(b); ObjectSetInteger(m_chart_id, b.Name(), OBJPROP_ZORDER, 200);
```

### Layer 3: Pressed(false) Reset

Add `Pressed(false)` at the start of EVERY button handler:
```cpp
void CDashboard::OnAutoT() {
   m_btnAutoTrade.Pressed(false);  // Reset toggle state
   m_auto = !m_auto;
   m_btnAutoTrade.Text(m_auto ? "AUTO TRADE: ON" : "AUTO TRADE: OFF");
   m_btnAutoTrade.ColorBackground(m_auto ? CLR_SUCCESS : CLR_BTN_OFF);
   MarkDirty();
}
```

### Layer 4: Block Event Storm

In OnChartEvent, block `CHARTEVENT_OBJECT_CHANGE` from reaching CAppDialog:
```cpp
// OBJECT_CHANGE fires every time OnTimer updates a label — creates event storm
// Also fires when HandleDirectClick resets OBJPROP_STATE — causes re-entry
if(!handled && id != CHARTEVENT_CHART_CHANGE && id != CHARTEVENT_OBJECT_CHANGE)
   g_dashboard.ChartEvent(id, lparam, dparam, sparam);
```

### Layer 5: OBJPROP_STATE Guard (prevents double-toggle)

**This is the fix for "buttons flash then revert to original state".**

When `ObjectSetInteger(OBJPROP_STATE, false)` is called in HandleDirectClick, MT5 generates a secondary `CHARTEVENT_OBJECT_CLICK` or `CHARTEVENT_OBJECT_CHANGE` event. Without a guard, HandleDirectClick fires **twice** on a single user click:

```
Click 1 (user):    STATE=true  → handler toggles ON→OFF ✓
Click 2 (phantom): STATE=false → handler toggles OFF→ON ✗ (REVERTED!)
```

**The fix — check STATE before processing:**
```cpp
bool CDashboard::HandleDirectClick(const string &objName)
{
   // Only process real user clicks (STATE=true)
   // Skip programmatic resets (STATE already false) → prevents double-toggle
   if(ObjectGetInteger(m_chart_id, objName, OBJPROP_STATE) == 0)
      return false;
   
   ObjectSetInteger(m_chart_id, objName, OBJPROP_STATE, false);
   // ... button matching ...
}
```

## CHECKLIST FOR NEW EA PROJECTS

- [ ] `HandleDirectClick()` method with ALL buttons mapped
- [ ] `HandleDirectClick()` has `OBJPROP_STATE == 0` guard at the top
- [ ] `OnChartEvent` intercepts clicks BEFORE `ChartEvent()`
- [ ] `OnChartEvent` does NOT `return;` after HandleDirectClick (use `bool handled` flag)
- [ ] `CHARTEVENT_OBJECT_CHANGE` blocked from `ChartEvent()`
- [ ] `CtrlShow/CtrlShowBtn/CtrlShowEdit/CtrlHide` with layered ZORDER
- [ ] `MB()` sets ZORDER=200
- [ ] ALL button handlers start with `Pressed(false)`
- [ ] `MarkDirtyPublic()` only on `CHARTEVENT_OBJECT_ENDEDIT`
- [ ] Command queue dispatcher runs AFTER HandleDirectClick (never behind early return)

## WHAT DOES NOT WORK (tried and failed)

| Attempt | Approach | Why it fails |
|---|---|---|
| 1 | ZORDER alone | CAppDialog internal routing still swallows events |
| 2 | + Pressed(false) | CAppDialog may not dispatch the event at all |
| 3 | + Block OBJECT_CHANGE | Toggle state and ZORDER issues remain |
| 4 | + HandleDirectClick with `return;` | Command queue never processes; action buttons silently fail |
| 5 | + HandleDirectClick without STATE guard | `OBJPROP_STATE` reset generates phantom event → double-toggle → buttons flash then revert |
| **6** | **ALL 5 layers together** | **✅ 100% reliable** |

**Only the combination of ALL 5 layers guarantees 100% click reliability.**
