/**
 * Shared helpers and picklist options for the RPM Command console.
 * Option values must match the restricted picklists on the objects.
 */

export const CALL_OUTCOMES = [
    { label: 'Spoke with patient', value: 'Spoke with patient' },
    { label: 'Spoke with caregiver', value: 'Spoke with caregiver' },
    { label: 'Left voicemail', value: 'Left voicemail' },
    { label: 'No answer after 3 tries', value: 'No answer after 3 tries' }
];

export const SYMPTOMS = [
    { label: 'None reported', value: 'None reported' },
    { label: 'Symptoms present - advised 911/ER', value: 'Symptoms present - advised 911/ER' },
    { label: 'Could not assess', value: 'Could not assess' }
];

export const PROVIDER_NOTIFIED = [
    { label: 'Yes - primary provider', value: 'Yes - primary provider' },
    { label: 'Yes - covering provider', value: 'Yes - covering provider' },
    { label: 'Not yet', value: 'Not yet' }
];

export const DISPOSITIONS = [
    { label: 'Recheck scheduled', value: 'Recheck scheduled' },
    { label: 'Medication adjusted by provider', value: 'Medication adjusted by provider' },
    { label: 'Advised ER evaluation', value: 'Advised ER evaluation' },
    { label: 'Coaching provided', value: 'Coaching provided' },
    { label: 'No change needed', value: 'No change needed' }
];

export const ACTIVITIES = [
    { label: 'Reviewed readings', value: 'Reviewed readings' },
    { label: 'Phone call with patient', value: 'Phone call with patient' },
    { label: 'Medication review with provider', value: 'Medication review with provider' },
    { label: 'Device troubleshooting', value: 'Device troubleshooting' },
    { label: 'Care plan update', value: 'Care plan update' },
    { label: 'Call with caregiver', value: 'Call with caregiver' },
    { label: 'Other', value: 'Other' }
];

export const STEPS = ['New', 'Checked', 'Assigned', 'Patient Called', 'Provider Reviewed', 'Closed'];

/** Turns an Apex/LDS error into one readable line. */
export function reduceError(error) {
    if (!error) {
        return 'Unknown error';
    }
    if (typeof error === 'string') {
        return error;
    }
    const body = error.body;
    if (body) {
        if (Array.isArray(body)) {
            return body.map((b) => b.message).join(', ');
        }
        if (body.message) {
            return body.message;
        }
        if (body.pageErrors && body.pageErrors.length) {
            return body.pageErrors[0].message;
        }
    }
    return error.message || 'Unknown error';
}

export function formatDateTime(value) {
    if (!value) {
        return '—';
    }
    const d = new Date(value);
    return d.toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
}

export function formatDate(value) {
    if (!value) {
        return '—';
    }
    // Date-only values arrive as YYYY-MM-DD; parse as local noon to avoid TZ shifts
    const d = typeof value === 'string' && value.length === 10 ? new Date(value + 'T12:00:00') : new Date(value);
    return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

export function daysAgo(value) {
    if (!value) {
        return null;
    }
    return Math.floor((Date.now() - new Date(value).getTime()) / 86400000);
}

export function riskClass(risk) {
    if (risk === 'RED') {
        return 'rpm-tag rpm-tag_rose';
    }
    if (risk === 'YELLOW') {
        return 'rpm-tag rpm-tag_amber';
    }
    return 'rpm-tag rpm-tag_emerald';
}

export function riskLabel(risk) {
    if (risk === 'RED') {
        return 'Red';
    }
    if (risk === 'YELLOW') {
        return 'Yellow';
    }
    return 'Green';
}

export function severityClass(severity) {
    if (severity === 'Critical') {
        return 'rpm-tag rpm-tag_rose';
    }
    if (severity === 'Urgent') {
        return 'rpm-tag rpm-tag_amber';
    }
    return 'rpm-tag rpm-tag_indigo';
}

export function severityLabel(severity) {
    if (severity === 'Critical') {
        return 'Critical';
    }
    if (severity === 'Urgent') {
        return 'Urgent';
    }
    return 'Routine';
}

/** What each RPM code means, shown inside the CPT pill. */
export const CPT_LABELS = {
    99453: 'Setup',
    99454: 'Device, 16+ days',
    99445: 'Device, 2–15 days',
    99457: 'First 20 min',
    99458: 'Each extra 20 min',
    99470: 'First 10 min'
};

/** "99454,99457,99458x2" -> [{ key, code, units, label }] */
export function parseCodes(codes) {
    if (!codes) {
        return [];
    }
    return codes
        .split(',')
        .map((c) => c.trim())
        .filter((c) => c)
        .map((c) => {
            const [code, units] = c.split('x');
            return { key: c, code, units: units ? Number(units) : 1, text: units ? `${code} ×${units}` : code, label: CPT_LABELS[code] || '' };
        });
}

/** Width and colour for a progress bar toward a goal. */
export function meter(value, goal) {
    const v = Number(value || 0);
    const pct = Math.min(100, (v / goal) * 100);
    return {
        value: v,
        goal,
        style: `width:${pct}%`,
        fillClass: pct >= 100 ? 'rpm-track__fill rpm-track__fill_full' : 'rpm-track__fill'
    };
}

/** Plain-language explanation of how a billing row's codes were reached. */
export function billingAudit(b) {
    const days = Number(b.readingDays || 0);
    const mins = Number(b.minutes || 0);
    const codes = parseCodes(b.codes).map((c) => c.code);
    const lines = [`${days} reading days counted this month`, `${mins} care minutes logged, ${b.interactive ? 'with' : 'without'} interactive communication`];
    if (b.blockedReason) {
        lines.push('Stopped: ' + b.blockedReason);
        return lines;
    }
    if (codes.includes('99453')) {
        lines.push('99453 earned: first month with 2 or more reading days');
    }
    if (codes.includes('99454')) {
        lines.push('99454 earned: 16 or more reading days');
    } else if (codes.includes('99445')) {
        lines.push(`99445 earned: 2–15 reading days (${16 - days} more would reach 99454)`);
    } else {
        lines.push('Under 2 reading days: no device code yet');
    }
    if (!b.interactive) {
        lines.push('No live call or video logged: management codes need interactive communication');
    } else if (codes.includes('99457')) {
        lines.push('99457 earned: 20 or more interactive minutes');
        lines.push(codes.includes('99458') ? '99458 earned for each further 20 minutes' : `${40 - mins} more minutes would add 99458`);
    } else if (codes.includes('99470')) {
        lines.push(`99470 earned: 10–19 interactive minutes (${20 - mins} more would reach 99457)`);
    } else {
        lines.push('Under 10 interactive minutes: no management code yet');
    }
    return lines;
}

/** Fires the console-wide navigation event. */
export function navigate(cmp, tab, detail = {}) {
    cmp.dispatchEvent(
        new CustomEvent('rpmnavigate', {
            detail: { tab, ...detail },
            bubbles: true,
            composed: true
        })
    );
}
