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
        return this.critical ? 'Critical alert — record the patient call' : 'Record the patient call';
    }

    get instruction() {
        return this.critical
            ? 'Required before this alert can move forward. It becomes part of the permanent history.'
            : 'Record whether you reached the patient. Symptoms and provider are optional for this alert.';
    }

    get saveVariant() {
        return this.critical ? 'destructive' : 'brand';
    }

    get showEr() {
        return this.symptoms === 'Symptoms present - advised 911/ER';
    }

    handleOutcome(e) {
        this.outcome = e.detail.value;
    }
    handleSymptoms(e) {
        this.symptoms = e.detail.value;
    }
    handleProvider(e) {
        this.provider = e.detail.value;
    }
    handleNote(e) {
        this.note = e.target.value;
    }

    cancel() {
        this.close(null);
    }

    save() {
        if (!this.outcome || (this.critical && (!this.symptoms || !this.provider))) {
            this.error = this.critical ? 'Please answer all three questions before saving.' : 'Please record whether you reached the patient.';
            return;
        }
        this.close({ outcome: this.outcome, symptoms: this.symptoms, provider: this.provider, note: this.note });
    }
}
