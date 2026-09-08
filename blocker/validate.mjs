import {readFile} from 'node:fs/promises';
import {validateSchedule,activeWindows} from './extension/schedule.mjs';
const plan = validateSchedule(JSON.parse(await readFile(new URL('./schedule.json',import.meta.url),'utf8')));
console.log(JSON.stringify({valid:true,windows:plan.windows.length,currentlyActive:activeWindows(plan,Date.now()).length}));
