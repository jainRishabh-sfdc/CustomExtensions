/**
 * Description    : Single source of the current time so tests can freeze it.
 * Developer Name : Rishabh Jain
 * Created Date   : Oct 15, 2026
 */
/**
 * Single source of "now" so tests can freeze time.
 */
public inherited sharing class RpmClock {
    @TestVisible
    private static Datetime fixedNow;

    public static Datetime now() {
        return fixedNow != null ? fixedNow : Datetime.now();
    }

    public static Date today() {
        return now().date();
    }
}
