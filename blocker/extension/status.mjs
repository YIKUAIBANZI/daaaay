async function show() {
  const {status,syncedAt} = await chrome.storage.local.get(['status','syncedAt']);
  document.querySelector('#state').textContent = status?.active === true
    ? `学习时段中，抖音访问已拦截。当前结束时间：${new Date(status.until).toLocaleString('zh-CN',{timeZone:'Asia/Shanghai'})}。`
    : status?.active === false ? '当前没有正在执行的屏蔽时段。' : '屏蔽状态尚未确认。';
  document.querySelector('#detail').textContent = status?.syncError || (syncedAt ? `日程上次同步：${new Date(syncedAt).toLocaleTimeString('zh-CN',{timeZone:'Asia/Shanghai'})}` : '尚未同步日程。');
}
document.querySelector('#refresh').addEventListener('click',async()=>{await chrome.runtime.sendMessage({type:'refresh'});await show();});
chrome.storage.onChanged.addListener(show);
await chrome.runtime.sendMessage({type:'refresh'});
await show();
