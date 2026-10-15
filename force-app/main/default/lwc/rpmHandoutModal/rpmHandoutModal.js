import { api } from 'lwc';
import LightningModal from 'lightning/modal';

/**
 * Four-step device handout. Closes with
 * { patientId, identity, training, testReading, loaner } or null.
 * The server re-checks every box before the device goes live.
 */
export default class RpmHandoutModal extends LightningModal {
    @api deviceLabel;
    @api model;
    @api imei;
    @api patients = [];

    step = 1;
    patientId;
    identity = false;
    training = false;
    testReading = false;
    loaner = false;
    error;

    get bars() {
        return [1, 2, 3, 4].map((i) => ({ key: 'b' + i, cls: i <= this.step ? 'rpm-bar rpm-bar_done' : 'rpm-bar' }));
    }

    get isStep1() {
        return this.step === 1;
    }
    get isStep2() {
        return this.step === 2;
    }
    get isStep3() {
        return this.step === 3;
    }
    get isStep4() {
        return this.step === 4;
    }

    get nextLabel() {
        return this.step === 1 ? 'Numbers match the box' : 'Continue';
    }

    get patientOptions() {
        return (this.patients || []).map((p) => ({ label: p.name, value: p.id }));
    }

    get patientName() {
        const p = (this.patients || []).find((x) => x.id === this.patientId);
        return p ? p.name : '';
    }

    handlePatient(e) {
        this.patientId = e.detail.value;
    }
    handleIdentity(e) {
        this.identity = e.target.checked;
    }
    handleTraining(e) {
        this.training = e.target.checked;
    }
    handleTest(e) {
        this.testReading = e.target.checked;
    }
    handleLoaner(e) {
        this.loaner = e.target.checked;
    }

    next() {
        this.error = undefined;
        if (this.step === 2 && (!this.patientId || !this.identity)) {
            this.error = 'Choose the patient and confirm both identifiers.';
            return;
        }
        if (this.step === 3 && !(this.training && this.testReading && this.loaner)) {
            this.error = 'All three checks are required before a device goes live.';
            return;
        }
        this.step += 1;
    }

    cancel() {
        this.close(null);
    }

    finish() {
        this.close({
            patientId: this.patientId,
            identity: this.identity,
            training: this.training,
            testReading: this.testReading,
            loaner: this.loaner
        });
    }
}
