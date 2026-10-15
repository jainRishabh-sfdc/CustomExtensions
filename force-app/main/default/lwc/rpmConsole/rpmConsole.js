import { LightningElement } from 'lwc';

const TABS = [
    { key: 'today', label: 'Today' },
    { key: 'patients', label: 'Patients' },
    { key: 'alerts', label: 'Alerts' },
    { key: 'devices', label: 'Devices' },
    { key: 'billing', label: 'Billing' }
];

/**
 * Console shell. Each board is created fresh when its tab opens, so data is
 * always current. Child boards ask to move with the bubbling `rpmnavigate`
 * event: { tab, patientId?, risk?, filter? }.
 */
export default class RpmConsole extends LightningElement {
    active = 'today';
    patientId;
    patientRisk;
    alertFilter;

    get tabs() {
        return TABS.map((t) => ({
            ...t,
            selected: t.key === this.active ? 'true' : 'false',
            cls: t.key === this.active ? 'rpm-tab rpm-tab_on' : 'rpm-tab'
        }));
    }

    get isToday() {
        return this.active === 'today';
    }
    get isPatients() {
        return this.active === 'patients';
    }
    get isAlerts() {
        return this.active === 'alerts';
    }
    get isDevices() {
        return this.active === 'devices';
    }
    get isBilling() {
        return this.active === 'billing';
    }

    handleTab(event) {
        this.patientId = undefined;
        this.patientRisk = undefined;
        this.alertFilter = undefined;
        this.active = event.currentTarget.dataset.tab;
    }

    handleNavigate(event) {
        event.stopPropagation();
        const { tab, patientId, risk, filter } = event.detail || {};
        this.patientId = patientId;
        this.patientRisk = risk;
        this.alertFilter = filter;
        // force a fresh board even when staying on the same tab
        this.active = undefined;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        Promise.resolve().then(() => {
            this.active = tab || 'today';
        });
    }
}
