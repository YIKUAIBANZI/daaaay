import {validateSchedule, activeWindows, nextBoundary, blockingRules} from './schedule.mjs';

async function refresh() {
  const saved = await chrome.storage.local.get(['plan']);
  let plan;
  try { plan = validateSchedule(saved.plan); } catch { plan = {version:1,windows:[]}; }
  let syncError = null;
  let syncedAt = null;
  try {
    const response = await fetch('http://127.0.0.1:18764/schedule', {
      cache:'no-store', signal:AbortSignal.timeout(3000)
    });
    if (!response.ok) throw new Error(`同步服务返回 ${response.status}`);
    plan = validateSchedule(await response.json());
    syncedAt = new Date().toISOString();
    await chrome.storage.local.set({plan, syncedAt});
  } catch (error) {
    syncError = `无法同步：${error.message}。沿用上次有效日程，到原定结束时间解除。`;
  }

  const now = Date.now();
  const active = activeWindows(plan, now);
  await chrome.declarativeNetRequest.updateDynamicRules({removeRuleIds:[1], addRules:blockingRules(active.length > 0)});
  const next = nextBoundary(plan, now);
  await chrome.alarms.clear('boundary');
  if (next !== null) await chrome.alarms.create('boundary', {when:Math.max(next,Date.now()+1000)});
  await chrome.action.setBadgeText({text:active.length ? '专注' : syncError ? '!' : ''});
  await chrome.action.setBadgeBackgroundColor({color:active.length ? '#295a43' : '#956622'});
  await chrome.storage.local.set({status:{active:active.length > 0, until:active.length ? Math.max(...active.map(w=>Date.parse(w.end))) : null, syncError, checkedAt:new Date().toISOString()}});

  if (active.length) {
    // Only inspect currently open Douyin tabs; never read history or other sites.
    const tabs = await chrome.tabs.query({url:['*://douyin.com/*','*://*.douyin.com/*']});
    await Promise.allSettled(tabs.map(tab => chrome.tabs.update(tab.id, {url:chrome.runtime.getURL('status.html')})));
  }
}
let queue = Promise.resolve();
function run() {
  queue = queue.catch(()=>{}).then(refresh).catch(async error => {
    await chrome.action.setBadgeText({text:'!'});
    await chrome.storage.local.set({status:{active:null,syncError:`屏蔽状态未确认：${error.message}`}});
  });
  return queue;
}
chrome.alarms.onAlarm.addListener(()=>{void run();});
chrome.runtime.onInstalled.addListener(()=>{void initialize();});
chrome.runtime.onStartup.addListener(()=>{void initialize();});
chrome.runtime.onMessage.addListener((message, sender, reply)=>{
  if (message?.type !== 'refresh') return false;
  run().then(()=>reply({ok:true}));
  return true;
});
async function initialize() {
  await chrome.alarms.create('sync', {periodInMinutes:0.5});
  await run();
}
// Service workers may restart without an onStartup event.
void initialize();
