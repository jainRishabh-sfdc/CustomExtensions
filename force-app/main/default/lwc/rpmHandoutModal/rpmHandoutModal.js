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

    get steps() {
        return ['Right cuff', 'Right patient', 'Trained', 'Live'].map((label, i) => ({
            key: 's' + i,
            label,
            cls: i < this.step ? 'rpm-step4 rpm-step4_on' : 'rpm-step4'
        }));
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
        return this.step === 1 ? 'Label matches' : 'Continue';
    }

    get patientOptions() {
        return (this.patients || []).map((p) => ({ label: p.name, value: p.id, selected: p.id === this.patientId }));
    }

    get patientName() {
        const p = (this.patients || []).find((x) => x.id === this.patientId);
        return p ? p.name : '';
    }

    handlePatient(e) {
        this.patientId = e.target.value;
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
            this.error = 'Choose the patient and confirm name and date of birth.';
            return;
        }
        if (this.step === 3 && !(this.training && this.testReading && this.loaner)) {
            this.error = 'All three checks are needed before the cuff goes live.';
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
