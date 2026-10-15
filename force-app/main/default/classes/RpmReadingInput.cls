/**
 * Description    : Vendor-neutral reading payload accepted by the readings API.
 * Developer Name : Rishabh Jain
 * Created Date   : Oct 15, 2026
 */
/**
 * Canonical, vendor-neutral reading format accepted by /rpm/v1/readings.
 * Each device vendor adapter (Smart Meter, Tenovi, ...) maps its own webhook
 * payload into this shape before posting.
 *
 * Example:
 * {"eventId":"sm-88123","imei":"356938035643809","measuredAt":"2026-08-09T07:41:00Z",
 *  "type":"Blood Pressure","systolic":181,"diastolic":112,"pulse":96,"battery":91,"signal":-69}
 */
public class RpmReadingInput {
    public String eventId;
    public String imei;
    public Datetime measuredAt;
    public String type;
    public Integer systolic;
    public Integer diastolic;
    public Integer pulse;
    public Decimal weightLb;
    public Integer battery;
    public Integer signal;
}
