import { LightningElement } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import RPM_FONTS from '@salesforce/resourceUrl/rpmFonts';
import getToday from '@salesforce/apex/RpmConsoleController.getToday';

const TABS = [
    { key: 'today', label: 'Today' },
    { key: 'patients', label: 'Patients' },
    { key: 'alerts', label: 'Alerts' },
    { key: 'devices', label: 'Devices' },
    { key: 'billing', label: 'Billing' }
];
const THEME_KEY = 'rpmCommandTheme';

/**
 * Console shell: header, care-time stopwatch, Day / Night shift toggle and
 * the five boards. Each board is created fresh when its tab opens.
 * Child events:
 *   rpmnavigate      { tab, patientId?, risk?, filter? }
 *   rpmpatientselect { id, name }  -> stopwatch follows the open patient
 *   rpmrefresh                     -> re-count the tab badges
 */
export default class RpmConsole extends LightningElement {
    active = 'today';
    patientId;
    patientRisk;
    alertFilter;
    presetMinutes;

    theme = 'day';
    counts = {};

    selectedPatientId;
    selectedPatientName;
    seconds = 0;
    running = false;
    intervalId;

    connectedCallback() {
        try {
            const saved = window.localStorage.getItem(THEME_KEY);
            if (saved === 'night' || saved === 'day') {
                this.theme = saved;
            }
        } catch (e) {
            // storage can be blocked; Day is the default
        }
        loadStyle(this, RPM_FONTS + '/fonts.css').catch(() => {
            // fonts are optional; the system font stack takes over
        });
        this.loadCounts();
    }

    disconnectedCallback() {
        this.stopInterval();
    }

    async loadCounts() {
        try {
            this.counts = await getToday();
        } catch (e) {
            this.counts = {};
        }
    }

    // ---------- theme

    get shellClass() {
        return this.theme === 'night' ? 'rpm-shell rpm-shell_night' : 'rpm-shell';
    }
    get dayClass() {
        return this.theme === 'day' ? 'rpm-theme__on' : '';
    }
    get nightClass() {
        return this.theme === 'night' ? 'rpm-theme__on' : '';
    }
    setTheme(event) {
        this.theme = event.currentTarget.dataset.theme;
        try {
            window.localStorage.setItem(THEME_KEY, this.theme);
        } catch (e) {
            // ignore
        }
    }

    // ---------- tabs

    get tabs() {
        const badges = { alerts: this.counts.healthOpen, devices: this.counts.deviceOpen };
        return TABS.map((t) => ({
            ...t,
            badge: badges[t.key] || null,
            selected: t.key === this.active ? 'true' : 'false',
            cls: t.key === this.active ? 'rpm-tabs__tab rpm-tabs__tab_on' : 'rpm-tabs__tab'
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
        this.open(event.currentTarget.dataset.tab, {});
    }

    handleNavigate(event) {
        event.stopPropagation();
        const { tab, ...rest } = event.detail || {};
        this.open(tab || 'today', rest);
    }

    open(tab, { patientId, risk, filter, minutes } = {}) {
        this.patientId = patientId;
        this.patientRisk = risk;
        this.alertFilter = filter;
        this.presetMinutes = minutes;
        this.active = undefined;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        Promise.resolve().then(() => {
            this.active = tab;
        });
        this.loadCounts();
    }

    handlePatientSelect(event) {
        event.stopPropagation();
        this.selectedPatientId = event.detail.id;
        this.selectedPatientName = event.detail.name;
    }

    // ---------- stopwatch

    get timerFor() {
        return this.selectedPatientName ? `Care time for ${this.selectedPatientName.split(' ')[0]}` : 'Care time';
    }
    get timerText() {
        const m = String(Math.floor(this.seconds / 60)).padStart(2, '0');
        const s = String(this.seconds % 60).padStart(2, '0');
        return `${m}:${s}`;
    }
    get timerValueClass() {
        return this.running ? 'rpm-timer__v rpm-timer__v_run' : 'rpm-timer__v';
    }
    get timerButton() {
        if (this.running) {
            return 'Pause';
        }
        return this.seconds ? 'Resume' : 'Start';
    }

    toggleTimer() {
        if (this.running) {
            this.stopInterval();
            this.running = false;
            return;
        }
        this.running = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.intervalId = setInterval(() => {
            this.seconds += 1;
        }, 1000);
    }

    stopInterval() {
        if (this.intervalId) {
            clearInterval(this.intervalId);
            this.intervalId = undefined;
        }
    }

    applyTimer() {
        if (!this.seconds) {
            this.toast('Start the stopwatch first', 'warning');
            return;
        }
        if (!this.selectedPatientId) {
            this.toast('Open a patient on the Patients board first', 'warning');
            return;
        }
        const minutes = Math.max(1, Math.ceil(this.seconds / 60));
        this.stopInterval();
        this.running = false;
        this.seconds = 0;
        this.open('patients', { patientId: this.selectedPatientId, minutes });
        this.toast(`${minutes} min ready to log for ${this.selectedPatientName}. Pick the activity and press Log time.`, 'info');
    }

    toast(message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title: message, variant }));
    }
}
