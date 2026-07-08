# 图表渲染规范 — 1:1 还原参考

> **使用说明：** 按本文档的规范实现图表，数据源用实际数据替换。CSS、参数值、渲染结构严格按文档，禁止自行修改。

## 设计参数（当前调好的值）

```json
{
  "barGap": 2,
  "barOff": 6,
  "barR": 3,
  "barW": 20,
  "cH": 160,
  "statsH": 60,
  "showY": true,
  "yW": 48,
  "yTicks": 5,
  "ghO": 6,
  "xS1": 10,
  "xPad": 2,
  "autoFS": true,
  "fsMax": 12,
  "manFS": 10,
  "vg": 2,
  "pW": 1000
}
```

## 颜色值

```json
{
  "download": "#34d399",
  "upload": "#9d78fc",
  "future": "rgba(255,255,255,0.04)",
  "background": "#1a1a1e",
  "statsBg": "rgba(255,255,255,0.03)",
  "chartBg": "rgba(255,255,255,0.03)",
  "gridH": "rgba(255,255,255,0.06)",
  "gridV": "rgba(255,255,255,0.05)",
  "axisLine": "rgba(255,255,255,0.08)",
  "labelPrimary": "rgba(255,255,255,0.5)",
  "yaxisLabel": "rgba(255,255,255,0.3)",
  "tipBg": "#222222"
}
```

## CSS（直接复制使用）

```css
*{margin:0;padding:0;box-sizing:border-box}
body{background:#1a1a1e;color:#e0e0e0;font-family:-apple-system,sans-serif}
.bar-slot{position:relative}
.bar-slot .tip{display:none;position:absolute;bottom:100%;left:50%;transform:translateX(-50%);background:#222;color:#eee;font-size:10px;padding:3px 6px;border-radius:4px;white-space:nowrap;pointer-events:none;z-index:10}
.bar-slot:hover .tip{display:block}
.page{margin-bottom:40px}
.pg-title{font-size:13px;color:#666;margin-bottom:8px}
.stats{display:flex;gap:20px;padding:10px 14px;background:rgba(255,255,255,.03);border-radius:8px;margin-bottom:10px}
.stats .lbl{font-size:10px;color:#888}
.stats .val{font-size:16px;font-weight:700;font-variant-numeric:tabular-nums}
.stats .val.d{color:#34d399}.stats .val.u{color:#9d78fc}
.chart{background:rgba(255,255,255,.03);border-radius:8px;padding:12px;margin-bottom:8px;overflow:hidden}
.chart-name{font-size:11px;font-weight:600;color:#888;margin-bottom:6px}
.chart-body{display:flex}
.yaxis{flex-shrink:0;display:flex;flex-direction:column;justify-content:space-between}
.yaxis span{font-size:9px;color:rgba(255,255,255,.3);text-align:right;font-variant-numeric:tabular-nums}
.plot{flex:1;display:flex;flex-direction:column;min-width:0}
.plot-area{position:relative;border-left:1px solid rgba(255,255,255,.08);border-bottom:1px solid rgba(255,255,255,.08);overflow:hidden}
.grid-h{position:absolute;left:0;right:0;border-top:1px dashed rgba(255,255,255,.06)}
.gvl{position:absolute;top:0;bottom:0;border-left:1px dashed rgba(255,255,255,.05)}
.bars{display:flex;align-items:flex-end;position:absolute;inset:0}
.bar-slot{flex:1;display:flex;flex-direction:column;align-items:center;min-width:0}
.bar-top{flex:1;display:flex;flex-direction:column;justify-content:flex-end;align-items:center;width:100%}
.bar-rect{width:100%;border-radius:3px 3px 0 0}
.bar-val{font-weight:600;font-variant-numeric:tabular-nums;white-space:nowrap}
.bar-rect.d{background:#34d399}.bar-rect.u{background:#9d78fc}.bar-rect.e{background:rgba(255,255,255,.04)}
```

## 数据结构

```typescript
interface ChartPage {
  dn: number[];        // 下载流量数组（bytes）
  up: number[];        // 上传流量数组（bytes）
  l1: string[];        // 主标签数组（如 "00:00", "01:00"）
  fut: (index: number) => boolean;  // 判断是否为未来柱子
  t: string;           // 页面标题
  s1: number;          // 总下载（bytes）
  s2: number;          // 总上传（bytes）
  a1: number;          // 平均下载速度（bytes/s）
  a2: number;          // 平均上传速度（bytes/s）
}
```

## 算法

### niceMax — 计算 Y 轴最大值

```javascript
function niceMax(arr) {
  const p = Math.max(...arr, 1) * 1.2;
  const m = Math.pow(10, Math.floor(Math.log10(p)));
  const n = p / m;
  return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * m;
}
```

### fmt — 格式化字节数

```javascript
function fmt(b) {
  if (b === 0) return '0';
  if (b < 1024) return b + 'B';
  if (b < 1048576) return (b / 1024).toFixed(0) + 'KB';
  if (b < 1073741824) return (b / 1048576).toFixed(1) + 'MB';
  return (b / 1073741824).toFixed(2) + 'GB';
}
```

### fmtS — 格式化速度

```javascript
function fmtS(b) {
  if (b <= 0) return '0 KB/s';
  const kb = b / 1024;
  if (kb < 1024) return kb.toFixed(0) + 'KB/s';
  return (kb / 1024).toFixed(1) + 'MB/s';
}
```

### autoFontSize — 自动字号

```javascript
// 基于实际柱宽计算
const fontSize = Math.max(8, Math.min(fsMax, Math.round(barWidth * 0.4)));
```

## 渲染逻辑（render 函数伪代码）

```javascript
function render(config, pages) {
  const { barGap, barOff, barR, barW, cH, statsH, showY, yW, yTicks, xS1, xPad, autoFS, fsMax, vg, pW } = config;

  for (const pg of pages) {
    const { dn, up, l1, fut, t, s1, s2, a1, a2 } = pg;
    const n = dn.length;
    const sharedMax = niceMax([...dn, ...up]);

    // 1. 统计栏
    // <div class="page" style="width:{pW}px">
    //   <div class="pg-title">{t} — {n}根柱子</div>
    //   <div class="stats" style="min-height:{statsH}px">
    //     下载 {fmt(s1)} | 上传 {fmt(s2)} | 平均↓ {fmtS(a1)} | 平均↑ {fmtS(a2)}
    //   </div>

    // 2. 对每个数据集 [dn,'d','下载流量'], [up,'u','上传流量']
    for (const [data, clr, label] of [[dn,'d','下载流量'], [up,'u','上传流量']]) {
      const mx = sharedMax;

      // Y轴（如果 showY=true）
      // 共 yTicks 个标签，从 mx 到 0 均匀分布
      // 标签值 = mx * i / (yTicks-1)，i 从 yTicks-1 到 0

      // 水平网格线（共 yTicks-1 条）
      // 位置 = gt/(yTicks-1)*100 %，gt 从 1 到 yTicks-1

      // 柱子循环
      for (let i = 0; i < n; i++) {
        const val = data[i];
        const isFut = fut(i);
        const pct = mx > 0 ? (val / mx) * 100 : 0;
        const hPx = isFut ? 3 : Math.round(pct * cH / 100);

        // 柱槽 <div class="bar-slot" style="flex:0 0 {barW}px;margin-right:{barGap}px">
        //   tooltip: {l1[i]} {fmt(val)}
        //   <div class="bar-top" style="height:{cH}px">
        //     数值标签（非未来）: <div class="bar-val" style="margin-bottom:{vg}px;font-size:{autoFS?9:manFS}px;color:{d=#34d399/u=#9d78fc}">{fmt(val)}</div>
        //     柱子: <div class="bar-rect {isFut?'e':clr}" style="height:{hPx}px;border-radius:{barR}px {barR}px 0 0"></div>
        //   </div>
        // </div>

        // X轴标签
        // <div style="flex:0 0 {barW}px;text-align:center">
        //   <div style="font-size:{xS1}px;color:rgba(255,255,255,{isFut?.2:.5})">{l1[i]}</div>
        // </div>
      }

      // 图表容器结构
      // <div class="chart">
      //   <div class="chart-name">{label}</div>
      //   <div class="chart-body">
      //     [Y轴（可选）]
      //     <div class="plot">
      //       <div class="plot-area" style="height:{cH}px">
      //         [水平网格]
      //         <div class="bars" style="padding-left:{barOff}px">[柱子]</div>
      //       </div>
      //       <div class="xlabels" style="display:flex;padding-left:{barOff}px">[标签]</div>
      //     </div>
      //   </div>
      // </div>
    }
  }
}
```

## 自动字号（post-render）

渲染完成后，基于实际柱宽重新计算字号：

```javascript
requestAnimationFrame(() => {
  // 对每个图表的每个数据集
  const bw = barSlots[0].getBoundingClientRect().width;
  if (autoFS) {
    const fs = Math.max(8, Math.min(fsMax, Math.round(bw * 0.4)));
    barSlots.forEach(slot => {
      const val = slot.querySelector('.bar-val');
      if (val) val.style.fontSize = fs + 'px';
    });
  }
});
```

## 垂直网格线（post-render）

```javascript
// 在每两根柱子之间的间隙中心绘制
for (let i = 1; i < n; i++) {
  const r1 = slots[i-1].getBoundingClientRect();
  const r2 = slots[i].getBoundingClientRect();
  const x = (r1.right + r2.left) / 2 - areaRect.left;
  // <div class="gvl" style="left:{x}px"></div>
}
```
