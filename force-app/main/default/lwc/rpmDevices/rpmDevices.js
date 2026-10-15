import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningPrompt from 'lightning/prompt';
import getDevices from '@salesforce/apex/RpmConsoleController.getDevices';
import getPatients from '@salesforce/apex/RpmConsoleController.getPatients';
import assignDevice from '@salesforce/apex/RpmConsoleController.assignDevice';
import returnDeviceApex from '@salesforce/apex/RpmConsoleController.returnDevice';
import RpmHandoutModal from 'c/rpmHandoutModal';
import { reduceError, formatDateTime, navigate } from 'c/rpmUtils';

export default class RpmDevices extends LightningElement {
    data = { field: [], stock: [], returns: [], silentDays: 7 };
    loading = false;
    error;

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            this.data = await getDevices();
            this.error = undefined;
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.loading = false;
        }
    }

    label(d) {
        return d.serial || d.name;
    }

    get silentDays() {
        return this.data.silentDays;
    }

    get fieldRows() {
        return (this.data.field || [])
            .map((d) => {
                const attention = d.silent || d.lowBattery;
                return {
                    ...d,
                    label: this.label(d),
                    attention,
                    lastText: d.lastReading ? formatDateTime(d.lastReading) : 'never',
                    batteryText: d.battery === null || d.battery === undefined ? '—' : d.battery + '%',
                    statusText: d.silent ? (d.daysSilent === null || d.daysSilent === undefined ? 'Never sent' : `Silent ${d.daysSilent} days`) : d.lowBattery ? 'Battery low' : 'Working',
                    statusClass: d.silent ? 'rpm-chip rpm-chip_crit' : d.lowBattery ? 'rpm-chip rpm-chip_warn' : 'rpm-chip rpm-chip_ok'
                };
            })
            .sort((a, b) => Number(b.attention) - Number(a.attention));
    }

    get stockRows() {
        return (this.data.stock || []).map((d) => ({ ...d, label: this.label(d) }));
    }

    get returnRows() {
        return (this.data.returns || []).map((d) => ({ ...d, label: this.label(d) }));
    }

    get stockCount() {
        return this.stockRows.length;
    }
    get attentionCount() {
        return this.fieldRows.filter((d) => d.attention).length;
    }
    get healthyCount() {
        return this.fieldRows.length - this.attentionCount;
    }
    get returnCount() {
        return this.returnRows.length;
    }
    get noField() {
        return this.fieldRows.length === 0;
    }
    get noStock() {
        return this.stockRows.length === 0;
    }
    get noReturns() {
        return this.returnRows.length === 0;
    }

    async handOut(event) {
        const device = (this.data.stock || []).find((d) => d.id === event.currentTarget.dataset.id);
        let patients;
        try {
            patients = await getPatients({ risk: null });
        } catch (e) {
            this.toast(reduceError(e), 'error');
            return;
        }
        const result = await RpmHandoutModal.open({
            size: 'small',
            label: 'Hand out a device',
            deviceLabel: this.label(device),
            model: device.model,
            imei: device.imei,
            patients
        });
        if (!result) {
            return;
        }
        try {
            await assignDevice({
                deviceId: device.id,
                patientId: result.patientId,
                identityVerified: result.identity,
                trainingDone: result.training,
                testReading: result.testReading,
                loanerAck: result.loaner
            });
            this.toast(`${this.label(device)} is live — readings now land in the patient's chart`, 'success');
            await this.load();
        } catch (e) {
            this.toast(reduceError(e), 'error');
        }
    }

    async returnDevice(event) {
        const { id, label } = event.currentTarget.dataset;
        const reason = await LightningPrompt.open({
            message: `What is wrong with ${label}?`,
            label: 'Return device',
            defaultValue: 'Not working'
        });
        if (reason === null || reason === undefined) {
            return;
        }
        try {
            await returnDeviceApex({ deviceId: id, reason });
            this.toast(`${label} marked for return — hand out a replacement from stock`, 'success');
            await this.load();
        } catch (e) {
            this.toast(reduceError(e), 'error');
        }
    }

    openPatient(event) {
        navigate(this, 'patients', { patientId: event.currentTarget.dataset.id });
    }

    toast(message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title: message, variant }));
    }
}
