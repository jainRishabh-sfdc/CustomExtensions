import { LightningElement, api } from 'lwc';

const W = 720;
const H = 280;
const L = 40;
const R = 12;
const T = 14;
const B = 40;
const Y_MIN = 40;
const Y_MAX = 200;

/**
 * Blood-pressure trend chart drawn as plain SVG.
 * Inputs: readings [{id, at, sys, dia, pulse, flag}], the protocol lines and
 * the patient's personal target band.
 */
export default class RpmBpChart extends LightningElement {
    @api readings = [];
    @api alertLine = 150;
    @api criticalLine = 180;
    @api lowLine = 90;
    @api targetHigh;
    @api targetLow;

    width = W;
    height = H;

    get viewBox() {
        return `0 0 ${W} ${H}`;
    }

    get hasData() {
        return this.readings && this.readings.length > 0;
    }

    y(v) {
        const clamped = Math.max(Y_MIN, Math.min(Y_MAX, Number(v)));
        return T + ((Y_MAX - clamped) / (Y_MAX - Y_MIN)) * (H - T - B);
    }

    get range() {
        const times = this.readings.map((r) => new Date(r.at).getTime());
        const min = Math.min(...times);
        const max = Math.max(...times);
        const pad = 12 * 3600 * 1000;
        return { min: min - pad, max: max + pad };
    }

    x(t) {
        const { min, max } = this.range;
        return L + ((t - min) / (max - min || 1)) * (W - L - R);
    }

    get grid() {
        const lines = [];
        for (let v = Y_MIN; v <= Y_MAX; v += 20) {
            const y = this.y(v);
            lines.push({ key: 'g' + v, y, labelY: y + 3, label: v, x1: L, x2: W - R, labelX: L - 6 });
        }
        return lines;
    }

    line(value, cls, label) {
        if (value === null || value === undefined) {
            return null;
        }
        const y = this.y(value);
        return { key: cls, y, labelY: y - 4, cls, label: `${label} ${value}`, x1: L, x2: W - R, labelX: L + 4 };
    }

    get thresholds() {
        return [
            this.line(this.criticalLine, 'rpm-line_crit', 'emergency line'),
            this.line(this.alertLine, 'rpm-line_hot', 'call line'),
            this.line(this.lowLine, 'rpm-line_low', 'low line')
        ].filter((l) => l);
    }

    get target() {
        if (!this.targetHigh || !this.targetLow) {
            return null;
        }
        const y1 = this.y(this.targetHigh);
        const y2 = this.y(this.targetLow);
        return { x: L, y: y1, width: W - L - R, height: y2 - y1, labelX: W - R - 4, labelY: y1 - 4, label: `personal target ${this.targetLow}–${this.targetHigh}` };
    }

    get points() {
        const n = this.readings.length;
        const labelEvery = Math.max(1, Math.ceil(n / 14));
        return this.readings.map((r, i) => {
            const t = new Date(r.at).getTime();
            const x = this.x(t);
            const flagged = r.flag === 'critical' || r.flag === 'high' || r.flag === 'low';
            const d = new Date(t);
            return {
                key: r.id,
                x,
                sysY: this.y(r.sys),
                diaY: r.dia === null || r.dia === undefined ? null : this.y(r.dia),
                hasDia: r.dia !== null && r.dia !== undefined,
                sysCls: r.flag === 'critical' ? 'rpm-dot rpm-dot_crit' : flagged ? 'rpm-dot rpm-dot_hot' : 'rpm-dot',
                showValue: flagged,
                valueY: this.y(r.sys) - 9,
                value: r.sys,
                title: `${d.toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })} — ${r.sys}/${r.dia ?? '?'}, pulse ${r.pulse ?? '?'}`,
                showLabel: i % labelEvery === 0 || i === n - 1,
                label: d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
                labelY: H - B + 16,
                labelTransform: `rotate(-35 ${x} ${H - B + 16})`
            };
        });
    }

    get sysPath() {
        return this.points.map((p) => `${p.x},${p.sysY}`).join(' ');
    }
}
