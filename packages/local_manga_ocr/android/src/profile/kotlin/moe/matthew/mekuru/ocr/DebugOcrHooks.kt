package moe.matthew.mekuru.ocr
import org.json.JSONObject
object DebugOcrHooks {
    const val enabled=false
    fun detectorFixture(context: android.content.Context,args: JSONObject): JSONObject = error("unavailable")
    fun evaluate(context: android.content.Context,args: JSONObject): JSONObject = error("unavailable")
    fun accept(job: JSONObject)=false
    fun benchmarkEngine(args: JSONObject): PageOcrEngine? = null
    fun processor(job: JSONObject): ((JSONObject,JSONObject,()->Unit,(String)->Unit)->OcrPageOutput)? = null
}
