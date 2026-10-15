import { LightningElement, api } from 'lwc';

const W = 760;
const H = 290;
const L = 42;
const R = 14;
const T = 16;
const B = 36;
const Y_MIN = 50;
const Y_MAX = 200;

/**
 * Blood-pressure trend chart drawn as plain SVG.
 * Smooth systolic and diastolic lines with soft area fills, the patient's
 * target band, the protocol call and emergency lines, and a value badge on
 * every flagged reading.
 * Inputs: readings [{id, at, sys, dia, pulse, flag}], protocol lines, target band.
 */
export default class RpmBpChart extends LightningElement {
    @api readings = [];
    @api alertLine = 150;
    @api criticalLine = 180;
    @api lowLine = 90;
    @api targetHigh;
    @api targetLow;

    get viewBox() {
        return `0 0 ${W} ${H}`;
    }

    get hasData() {
        return Array.isArray(this.readings) && this.readings.length > 0;
    }

    y(v) {
        const c = Math.max(Y_MIN, Math.min(Y_MAX, Number(v)));
        return T + ((Y_MAX - c) / (Y_MAX - Y_MIN)) * (H - T - B);
    }

    get range() {
        const times = this.readings.map((r) => new Date(r.at).getTime());
        const pad = 10 * 3600 * 1000;
        return { min: Math.min(...times) - pad, max: Math.max(...times) + pad };
    }

    x(t) {
        const { min, max } = this.range;
        return L + ((t - min) / (max - min || 1)) * (W - L - R);
    }

    get grid() {
        const out = [];
        for (let v = 60; v <= Y_MAX; v += 20) {
            const y = this.y(v);
            out.push({ key: 'g' + v, y, ty: y + 3, label: v, x1: L, x2: W - R, tx: L - 8 });
        }
        return out;
    }

    get target() {
        if (!this.targetHigh || !this.targetLow) {
            return null;
        }
        const y1 = this.y(this.targetHigh);
        const y2 = this.y(this.targetLow);
        return { x: L, y: y1, w: W - L - R, h: y2 - y1, tx: W - R - 6, ty: y1 + 13, label: `Target ${this.targetLow}–${this.targetHigh}` };
    }

    get lines() {
        const out = [];
        if (this.criticalLine) {
            const y = this.y(this.criticalLine);
            out.push({ key: 'crit', y, ty: y - 5, x1: L, x2: W - R, tx: L + 6, cls: 'rpm-line rpm-line_crit', tcls: 'rpm-linelabel rpm-linelabel_crit', label: `Emergency ${this.criticalLine}` });
        }
        if (this.alertLine) {
            const y = this.y(this.alertLine);
            out.push({ key: 'call', y, ty: y - 5, x1: L, x2: W - R, tx: L + 6, cls: 'rpm-line rpm-line_call', tcls: 'rpm-linelabel rpm-linelabel_call', label: `Call line ${this.alertLine}` });
        }
        return out;
    }

    smooth(pts) {
        return pts
            .map((p, i) => {
                if (i === 0) {
                    return `M${p[0]},${p[1]}`;
                }
                const prev = pts[i - 1];
                const cx = (prev[0] + p[0]) / 2;
                return `C${cx},${prev[1]} ${cx},${p[1]} ${p[0]},${p[1]}`;
            })
            .join(' ');
    }

    area(pts) {
        const base = this.y(Y_MIN);
        return `${this.smooth(pts)} L${pts[pts.length - 1][0]},${base} L${pts[0][0]},${base} Z`;
    }

    get sorted() {
        return [...this.readings].sort((a, b) => new Date(a.at) - new Date(b.at));
    }

    get sysPts() {
        return this.sorted.map((r) => [this.x(new Date(r.at).getTime()), this.y(r.sys)]);
    }

    get diaPts() {
        return this.sorted.filter((r) => r.dia !== null && r.dia !== undefined).map((r) => [this.x(new Date(r.at).getTime()), this.y(r.dia)]);
    }

    get sysLine() {
        return this.smooth(this.sysPts);
    }
    get sysArea() {
        return this.area(this.sysPts);
    }
    get hasDia() {
        return this.diaPts.length > 1;
    }
    get diaLine() {
        return this.smooth(this.diaPts);
    }
    get diaArea() {
        return this.area(this.diaPts);
    }

    get points() {
        const rows = this.sorted;
        const every = Math.max(1, Math.ceil(rows.length / 10));
        return rows.map((r, i) => {
            const t = new Date(r.at);
            const x = this.x(t.getTime());
            const sy = this.y(r.sys);
            const flagged = r.flag === 'critical' || r.flag === 'high' || r.flag === 'low';
            const tone = r.flag === 'critical' ? 'crit' : 'warn';
            return {
                key: r.id,
                x,
                sysY: sy,
                hasDia: r.dia !== null && r.dia !== undefined,
                diaY: r.dia === null || r.dia === undefined ? 0 : this.y(r.dia),
                sysR: flagged ? 5.5 : 4,
                sysCls: flagged ? `rpm-pt rpm-pt_${tone}` : 'rpm-pt',
                flagged,
                badgeX: x - 20,
                badgeY: sy - 27,
                badgeCls: `rpm-badge rpm-badge_${tone}`,
                valueY: sy - 14,
                value: r.sys,
                title: `${t.toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })}: ${r.sys}/${r.dia ?? '?'}, pulse ${r.pulse ?? '?'}`,
                showLabel: i % every === 0 || i === rows.length - 1,
                labelY: H - 12,
                label: t.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
            };
        });
    }
}
