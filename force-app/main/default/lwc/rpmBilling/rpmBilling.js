import { LightningElement } from 'lwc';
import getBilling from '@salesforce/apex/RpmConsoleController.getBilling';
import { reduceError, formatDate, navigate } from 'c/rpmUtils';

function barStyle(value, goal) {
    const pct = Math.min(100, (Number(value || 0) / goal) * 100);
    return `width:${pct}%;background:${pct >= 100 ? '#177245' : '#9a6b10'}`;
}

export default class RpmBilling extends LightningElement {
    data = [];
    loading = false;
    error;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.data = await getBilling();
            this.error = undefined;
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.loading = false;
        }
    }

    get rows() {
        return [...this.data]
            .sort((a, b) => (a.patientName || '').localeCompare(b.patientName || ''))
            .map((r) => ({
                ...r,
                readingDays: r.readingDays || 0,
                minutes: r.minutes || 0,
                daysStyle: barStyle(r.readingDays, 16),
                minutesStyle: barStyle(r.minutes, 20),
                interactiveText: r.interactive ? 'Yes' : 'Not yet',
                statusClass:
                    r.status === 'Ready to Bill' || r.status === 'Billed'
                        ? 'rpm-chip rpm-chip_ok'
                        : r.status === 'Blocked'
                          ? 'rpm-chip rpm-chip_crit'
                          : 'rpm-chip rpm-chip_warn'
            }));
    }

    get noRows() {
        return !this.loading && this.data.length === 0;
    }

    get withCodes() {
        return this.data.filter((r) => r.codes).length;
    }
    get accruing() {
        return this.data.filter((r) => r.status === 'Accruing').length;
    }
    get blocked() {
        return this.data.filter((r) => r.status === 'Blocked').length;
    }

    get periodLabel() {
        const first = this.data[0];
        return first ? `${formatDate(first.periodStart)} – ${formatDate(first.periodEnd)}` : 'this month';
    }

    get rulesVersion() {
        const first = this.data[0];
        return first ? first.rulesVersion : '';
    }

    openPatient(event) {
        navigate(this, 'patients', { patientId: event.currentTarget.dataset.id });
    }
}
