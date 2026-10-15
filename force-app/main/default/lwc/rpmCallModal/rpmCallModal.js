import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import { CALL_OUTCOMES, SYMPTOMS, PROVIDER_NOTIFIED } from 'c/rpmUtils';

/**
 * Patient-call record. For Critical alerts all three answers are required
 * (the server enforces the same rule). Closes with
 * { outcome, symptoms, provider, note } or null when cancelled.
 */
export default class RpmCallModal extends LightningModal {
    @api patientName;
    @api summary;
    @api severity;

    outcome;
    symptoms;
    provider;
    note = '';
    error;

    outcomeOptions = CALL_OUTCOMES;
    symptomOptions = SYMPTOMS;
    providerOptions = PROVIDER_NOTIFIED;

    get critical() {
        return this.severity === 'Critical';
    }

    get heading() {
        return this.critical ? 'Record the call for this critical reading' : 'Record the call';
    }

    get instruction() {
        return this.critical
            ? 'All three answers are required and become part of the permanent history.'
            : 'Only the first answer is required for this alert.';
    }

    get saveClass() {
        return this.critical ? 'rpm-m__btn rpm-m__btn_danger' : 'rpm-m__btn rpm-m__btn_primary';
    }

    get showEr() {
        return this.symptoms === 'Symptoms present - advised 911/ER';
    }

    handleOutcome(e) {
        this.outcome = e.target.value;
    }
    handleSymptoms(e) {
        this.symptoms = e.target.value;
    }
    handleProvider(e) {
        this.provider = e.target.value;
    }
    handleNote(e) {
        this.note = e.target.value;
    }

    cancel() {
        this.close(null);
    }

    save() {
        if (!this.outcome || (this.critical && (!this.symptoms || !this.provider))) {
            this.error = this.critical ? 'Answer all three questions to save this call.' : 'Say whether you reached the patient to save this call.';
            return;
        }
        this.close({ outcome: this.outcome, symptoms: this.symptoms, provider: this.provider, note: this.note });
    }
}
