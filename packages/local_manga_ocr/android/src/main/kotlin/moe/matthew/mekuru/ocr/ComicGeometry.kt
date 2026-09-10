/*
 * Comic Text Detector postprocessing, ported from dmMaze/comic-text-detector
 * utils/textblock.py at 293ae8060b08f2ed323693019f9bd0c173af4eab.
 * GPL-3.0. Android port and bounded geometry handling: 2026-09-10.
 * Original project and corresponding source: see assets/licenses/COMIC-TEXT-DETECTOR.txt.
 */
package moe.matthew.mekuru.ocr

import kotlin.math.*

data class P(val x: Double, val y: Double) {
    operator fun plus(b: P) = P(x+b.x,y+b.y)
    operator fun minus(b: P) = P(x-b.x,y-b.y)
    operator fun times(n: Double) = P(x*n,y*n)
    fun norm() = hypot(x,y)
}
data class Box(val x1: Double,val y1: Double,val x2: Double,val y2: Double) {
    val area get() = max(0.0,x2-x1)*max(0.0,y2-y1)
    fun intersect(b: Box) = max(0.0,min(x2,b.x2)-max(x1,b.x1)) *
        max(0.0,min(y2,b.y2)-max(y1,b.y1))
    fun quad() = listOf(P(x1,y1),P(x2,y1),P(x2,y2),P(x1,y2))
    fun union(b: Box) = Box(min(x1,b.x1),min(y1,b.y1),max(x2,b.x2),max(y2,b.y2))
    fun list() = listOf(x1,y1,x2,y2)
}
fun bounds(line: List<P>) = Box(line.minOf { it.x },line.minOf { it.y },
    line.maxOf { it.x },line.maxOf { it.y })
data class DetectedBlock(var box: Box, val japanese: Boolean = true,
    var lines: MutableList<List<P>> = mutableListOf()) {
    var vertical = true
    var fontSize = 1.0
    var angle = 0.0
    var vector = P(0.0,1.0)
    var distances = listOf<Double>()
}
object ComicGeometry {
    fun examine(block: DetectedBlock, width: Int, sort: Boolean = true) {
        var v = P(0.0,0.0); var h = P(0.0,0.0)
        for (q in block.lines) {
            v += (q[2]+q[3]-q[0]-q[1])*.5
            h += (q[1]+q[2]-q[0]-q[3])*.5
        }
        block.vertical = v.norm() > h.norm() * if (block.japanese) 1 else 2
        block.vector = if (block.vertical) v else h
        block.fontSize = max(1.0, round((if (block.vertical) h.norm() else v.norm()) /
            block.lines.size.coerceAtLeast(1)))
        block.angle = atan2(block.vector.y,block.vector.x)*180/PI - if (block.vertical) 90 else 0
        if (abs(block.angle) < 3) block.angle = 0.0
        val origin = if (block.vertical) P(width.toDouble(),0.0) else P(0.0,0.0)
        fun distance(q: List<P>): Double {
            val center = (q[0]+q[2])*.5-origin
            return abs(center.x*block.vector.y-center.y*block.vector.x) /
                block.vector.norm().coerceAtLeast(.001)
        }
        if (sort) block.lines.sortBy { distance(it) }
        block.distances = block.lines.map { distance(it) }
    }
    private fun adjust(block: DetectedBlock, keepBox: Boolean) {
        val rect = block.lines.map { bounds(it) }.reduce { a,b -> a.union(b) }
        block.box = if (keepBox) block.box.union(rect) else rect
    }
    fun group(boxes: List<DetectedBlock>, lines: List<List<P>>, width: Int, height: Int,
              maskMean: (Box) -> Double): List<DetectedBlock> {
        val scattered = mutableListOf<DetectedBlock>()
        for (line in lines) {
            val rect = bounds(line)
            if (rect.area <= 0) continue
            val closest = boxes.maxByOrNull { it.box.intersect(rect)/rect.area }
            if (closest != null && closest.box.intersect(rect)/rect.area > .4) closest.lines.add(line)
            else if (maskMean(rect) >= .1) {
                scattered.add(DetectedBlock(rect, false, mutableListOf(line)).also { examine(it,width) })
            }
        }
        val result = mutableListOf<DetectedBlock>()
        for (block in boxes) {
            if (block.lines.isEmpty()) {
                if (maskMean(block.box) < .1) continue
                block.lines.add(block.box.quad())
            }
            examine(block,width)
            val groups = mutableListOf(mutableListOf(block.lines.first()))
            for (i in 1 until block.lines.size) {
                val a = block.lines[i-1]; val b = block.lines[i]
                val d = abs(block.distances[i]-block.distances[i-1])
                val split = (block.japanese || block.vertical) &&
                    bounds(a).intersect(bounds(b)) == 0.0 &&
                    (d > block.fontSize*2 ||
                        (block.vertical && abs(block.angle)<15 &&
                            (groups.last().size>1 || d>block.fontSize) &&
                            abs(a[0].y-b[0].y)>block.fontSize))
                if (split) groups.add(mutableListOf(b)) else groups.last().add(b)
            }
            for (group in groups) {
                result.add(DetectedBlock(block.box,block.japanese,group).also {
                    examine(it,width); adjust(it,groups.size==1)
                })
            }
        }
        // Unassigned lines use upstream orientation/size/spacing merge rules.
        for (vertical in listOf(false,true)) {
            val pending = scattered.filter { it.vertical==vertical }.sortedBy { it.distances[0] }.toMutableList()
            while (pending.isNotEmpty()) {
                val a = pending.removeAt(0)
                val iterator = pending.iterator()
                while (iterator.hasNext()) {
                    val b = iterator.next()
                    val ratio = a.fontSize/b.fontSize
                    val average = (a.fontSize*a.lines.size+b.fontSize)/(a.lines.size+1)
                    val cosine = (a.vector.x*b.vector.x+a.vector.y*b.vector.y)/
                        (a.vector.norm()*b.vector.norm()).coerceAtLeast(.001)
                    val intersects = bounds(a.lines.last()).intersect(bounds(b.lines.first()))>0
                    if (intersects || (ratio in 1/1.3..1.3 && abs(cosine)>=.866 &&
                        b.distances.last()-a.distances.last()<=2*average &&
                        (b.lines.first()[0]-a.lines.last()[0]).norm()<=average*2.5)) {
                        a.lines.addAll(b.lines); examine(a,width); iterator.remove()
                    }
                }
                adjust(a,false); result.add(a)
            }
        }
        val flip = result.count { it.japanese }>result.size/2
        val gridWidth = if (width>height) width/2.0 else width.toDouble()
        val area = gridWidth*height
        return result.sortedBy { block ->
            var x = (block.box.x1+block.box.x2)/2
            if (flip) x=width-x
            val y = (block.box.y1+block.box.y2)/2
            val gx = (x/gridWidth*3).toInt(); val gy = (y/height*4).toInt()
            (gy*3+gx)*area+1.2*(x-gx*gridWidth/3)+(y-gy*height/4.0) +
                if (width>height && gx>=3) area*12 else 0.0
        }
    }
}
