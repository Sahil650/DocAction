package com.docaction.app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.*
import org.opencv.imgproc.Imgproc

import java.io.File
import java.io.FileOutputStream
import ai.onnxruntime.*
import java.nio.FloatBuffer
import android.media.ExifInterface
import android.os.Handler
import android.os.Looper
import kotlin.concurrent.thread

class MainActivity: FlutterActivity() {

    private val CHANNEL = "edge_detection"
    private var ortEnv: OrtEnvironment? = null
    private var ortSession: OrtSession? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        OpenCVLoader.initDebug()
        // Removed eager initOrt() - handled via lazy loading in runOnnxInference

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->

                when (call.method) {
                    "detectCorners" -> {
                        val path = call.argument<String>("path")!!
                        thread {
                            var bitmap: Bitmap? = null
                            try {
                                bitmap = orientBitmap(path)
                                val points = detectDocument(bitmap)
                                Handler(Looper.getMainLooper()).post {
                                    if (points != null) {
                                        val ordered = orderPoints(points)
                                        val resultList = ordered.flatMap { listOf(it.x / bitmap.width, it.y / bitmap.height) }
                                        result.success(resultList)
                                    } else {
                                        result.success(null)
                                    }
                                }
                            } catch (e: Exception) {
                                Handler(Looper.getMainLooper()).post {
                                    Log.e("SCAN", "Error: ${e.message}")
                                    result.error("ERROR", e.message, null)
                                }
                            } finally {
                                bitmap?.recycle()
                            }
                        }
                    }
                    "warpPerspective" -> {
                        val path = call.argument<String>("path")!!
                        val points = call.argument<List<Double>>("points")!!
                        thread {
                            var bitmap: Bitmap? = null
                            var scanned: Bitmap? = null
                            try {
                                bitmap = orientBitmap(path)
                                val cvPoints = Array(4) { i -> 
                                    Point(points[i * 2] * bitmap.width, points[i * 2 + 1] * bitmap.height) 
                                }
                                scanned = warpDocument(bitmap, MatOfPoint2f(*cvPoints))
                                
                                val file = File(cacheDir, "scanned_${System.currentTimeMillis()}.jpg")
                                val fos = FileOutputStream(file)
                                scanned.compress(Bitmap.CompressFormat.JPEG, 90, fos)
                                fos.close()
                                
                                Handler(Looper.getMainLooper()).post {
                                    result.success(file.absolutePath)
                                }
                            } catch (e: Exception) {
                                Handler(Looper.getMainLooper()).post {
                                    result.error("ERROR", e.message, null)
                                }
                            } finally {
                                bitmap?.recycle()
                                scanned?.recycle()
                            }
                        }
                    }
                    "applyFilter" -> {
                        val path = call.argument<String>("path")!!
                        val filter = call.argument<String>("filter")!!
                        thread {
                            var bitmap: Bitmap? = null
                            var resultBitmap: Bitmap? = null
                            val src = Mat()
                            val filtered = Mat()
                            val gray = Mat()
                            val dilated = Mat()
                            val bg = Mat()
                            val diff = Mat()
                            val normalized = Mat()
                            val hsv = Mat()
                            val sharpenKernel = Mat()
                            val channels = ArrayList<Mat>()

                            try {
                                bitmap = orientBitmap(path)
                                Utils.bitmapToMat(bitmap, src)
                                
                                when (filter) {
                                    "gray" -> Imgproc.cvtColor(src, filtered, Imgproc.COLOR_BGR2GRAY)
                                    "bw" -> {
                                         Imgproc.cvtColor(src, gray, Imgproc.COLOR_BGR2GRAY)
                                         Imgproc.adaptiveThreshold(gray, filtered, 255.0, Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C, Imgproc.THRESH_BINARY, 11, 2.0)
                                    }
                                    "magic" -> {
                                        Imgproc.cvtColor(src, gray, Imgproc.COLOR_BGR2GRAY)
                                        val kernel = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(7.0, 7.0))
                                        Imgproc.dilate(gray, dilated, kernel)
                                        Imgproc.medianBlur(dilated, bg, 21)
                                        
                                        Core.absdiff(gray, bg, diff)
                                        Core.bitwise_not(diff, diff)
                                        
                                        diff.convertTo(normalized, CvType.CV_32F)
                                        Core.normalize(normalized, normalized, 0.0, 255.0, Core.NORM_MINMAX)
                                        normalized.convertTo(filtered, CvType.CV_8U)

                                        Imgproc.cvtColor(src, hsv, Imgproc.COLOR_BGR2HSV)
                                        Core.split(hsv, channels)
                                        
                                        val oldV = channels[2]
                                        channels[2] = filtered
                                        Core.merge(channels, hsv)
                                        Imgproc.cvtColor(hsv, filtered, Imgproc.COLOR_HSV2BGR)
                                        oldV.release()
                                        
                                        filtered.convertTo(filtered, -1, 1.2, 10.0)
                                        sharpenKernel.create(3, 3, CvType.CV_32F)
                                        sharpenKernel.put(0, 0, 0.0, -1.0, 0.0, -1.0, 5.0, -1.0, 0.0, -1.0, 0.0)
                                        Imgproc.filter2D(filtered, filtered, -1, sharpenKernel)
                                    }
                                    "rotate" -> {
                                        Core.rotate(src, filtered, Core.ROTATE_90_CLOCKWISE)
                                    }
                                    "adjust" -> {
                                        val contrast = call.argument<Double>("contrast") ?: 1.0
                                        val brightness = call.argument<Double>("brightness") ?: 0.0
                                        src.convertTo(filtered, -1, contrast, brightness)
                                    }
                                    else -> {
                                        src.convertTo(filtered, -1, 1.1, 5.0)
                                    }
                                }
                                
                                resultBitmap = Bitmap.createBitmap(filtered.cols(), filtered.rows(), Bitmap.Config.ARGB_8888)
                                Utils.matToBitmap(filtered, resultBitmap)
                                
                                val file = File(cacheDir, "filtered_${System.currentTimeMillis()}.jpg")
                                val fos = FileOutputStream(file)
                                resultBitmap.compress(Bitmap.CompressFormat.JPEG, 90, fos)
                                fos.close()
                                
                                Handler(Looper.getMainLooper()).post {
                                    result.success(file.absolutePath)
                                }
                            } catch (e: Exception) {
                                Handler(Looper.getMainLooper()).post {
                                    result.error("ERROR", e.message, null)
                                }
                            } finally {
                                bitmap?.recycle()
                                resultBitmap?.recycle()
                                releaseMats(src, filtered, gray, dilated, bg, diff, normalized, hsv, sharpenKernel)
                                for (m in channels) m.release()
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun orientBitmap(path: String): Bitmap {
        val original = BitmapFactory.decodeFile(path)
        val exif = ExifInterface(path)
        val orientation = exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        
        val matrix = android.graphics.Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            else -> return original
        }
        
        val result = Bitmap.createBitmap(original, 0, 0, original.width, original.height, matrix, true)
        if (result != original) {
            original.recycle()
        }
        return result
    }

    private fun releaseMats(vararg mats: Mat?) {
        for (mat in mats) {
            mat?.release()
        }
    }

    private fun initOrt() {
        if (ortEnv == null) {
            ortEnv = OrtEnvironment.getEnvironment()
        }
        if (ortSession == null) {
            try {
                // Try both possible asset paths
                val modelPath = "flutter_assets/assets/models/docquadnet256_trained_opset17.ort"
                Log.d("SCAN", "Attempting to load model from: $modelPath")
                val modelBytes = assets.open(modelPath).readBytes()
                ortSession = ortEnv?.createSession(modelBytes)
                Log.d("SCAN", "ONNX model loaded successfully. Inputs: ${ortSession?.inputNames}, Outputs: ${ortSession?.outputNames}")
            } catch (e: Exception) {
                Log.e("SCAN", "Failed to load ONNX model: ${e.message}")
                // Try alternate path just in case
                try {
                    val altPath = "assets/models/docquadnet256_trained_opset17.ort"
                    Log.d("SCAN", "Attempting alternate path: $altPath")
                    val modelBytes = assets.open(altPath).readBytes()
                    ortSession = ortEnv?.createSession(modelBytes)
                    Log.d("SCAN", "ONNX model loaded from alternate path.")
                } catch (e2: Exception) {
                    Log.e("SCAN", "All model load attempts failed: ${e2.message}")
                }
            }
        }
    }

    private fun detectDocument(bitmap: Bitmap): Array<Point>? {
        // Try ONNX first
        try {
            val points = runOnnxInference(bitmap)
            if (points != null) {
                Log.d("SCAN", "ONNX detection successful")
                return points
            }
        } catch (e: Exception) {
            Log.e("SCAN", "ONNX Inference failed: ${e.message}")
        }

        // Fallback to OpenCV
        Log.d("SCAN", "ONNX failed or no detection, falling back to OpenCV")
        val quad = detectDocumentOpenCV(bitmap)
        return quad?.toArray()
    }

    private fun runOnnxInference(bitmap: Bitmap): Array<Point>? {
        if (ortSession == null) {
            initOrt()
            if (ortSession == null) return null
        }

        val size = 256
        
        // 1. Letterbox preprocessing (padding to maintain aspect ratio)
        val w = bitmap.width.toFloat()
        val h = bitmap.height.toFloat()
        val scale = minOf(size / w, size / h)
        val nw = (w * scale).toInt()
        val nh = (h * scale).toInt()
        
        val resized = Bitmap.createScaledBitmap(bitmap, nw, nh, true)
        val letterboxed = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(letterboxed)
        canvas.drawColor(Color.BLACK)
        val left = (size - nw) / 2f
        val top = (size - nh) / 2f
        canvas.drawBitmap(resized, left, top, null)
        
        // 2. Preprocess: RGB, Normalized [0, 1], NCHW
        val floatBuffer = FloatBuffer.allocate(1 * 3 * size * size)
        val pixels = IntArray(size * size)
        letterboxed.getPixels(pixels, 0, size, 0, 0, size, size)

        // CHW format
        for (c in 0 until 3) {
            for (i in 0 until size * size) {
                val color = pixels[i]
                val channelValue = when (c) {
                    0 -> (color shr 16 and 0xFF) / 255.0f // R
                    1 -> (color shr 8 and 0xFF) / 255.0f  // G
                    else -> (color and 0xFF) / 255.0f     // B
                }
                floatBuffer.put(channelValue)
            }
        }
        floatBuffer.rewind()

        val inputName = ortSession?.inputNames?.iterator()?.next() ?: "input"
        val inputTensor = OnnxTensor.createTensor(ortEnv, floatBuffer, longArrayOf(1, 3, size.toLong(), size.toLong()))
        
        var results: OrtSession.Result? = null
        try {
            results = ortSession?.run(mapOf(inputName to inputTensor))
            
            if (results == null) return null

            val outputName = if (results.get("corner_heatmaps").isPresent) "corner_heatmaps" 
                            else if (results.count() > 0) results.iterator().next().key 
                            else null
            
            if (outputName == null) return null

            val outputHeatmapValue = results.get(outputName)
            if (!outputHeatmapValue.isPresent) return null
            
            val heatmapData: Array<Array<FloatArray>> = try {
                val tensor = outputHeatmapValue.get() as OnnxTensor
                val value = tensor.value as Array<*>
                value[0] as Array<Array<FloatArray>>
            } catch (e: Exception) {
                return null
            }
            
            val hH = heatmapData[0].size
            val hW = heatmapData[0][0].size
            val scaleH = size.toDouble() / hH
            val scaleW = size.toDouble() / hW

            val corners = Array(4) { Point() }
            for (c in 0 until 4) {
                val channel = heatmapData[c]
                var maxVal = -1e10f
                var maxX = 0; var maxY = 0
                for (y in 0 until hH) {
                    for (x in 0 until hW) {
                        val v = channel[y][x]
                        if (v > maxVal) { maxVal = v; maxX = x; maxY = y }
                    }
                }
                
                if (maxVal < -1.0f) return null
                
                var sumW = 0.0; var sumWX = 0.0; var sumWY = 0.0
                for (dy in -2..2) {
                    for (dx in -2..2) {
                        val py = maxY + dy; val px = maxX + dx
                        if (py in 0 until hH && px in 0 until hW) {
                            val v = channel[py][px]
                            val weight = Math.exp(((v - maxVal) / 1.0).toDouble()) 
                            sumW += weight; sumWX += weight * (px + 0.5); sumWY += weight * (py + 0.5)
                        }
                    }
                }
                val refinedX = (sumWX / sumW) * scaleW
                val refinedY = (sumWY / sumW) * scaleH
                corners[c].x = ((refinedX - left) / scale).toDouble()
                corners[c].y = ((refinedY - top) / scale).toDouble()
            }
            return corners
        } catch (e: Exception) {
            Log.e("SCAN", "Inference error: ${e.message}")
            return null
        } finally {
            inputTensor.close()
            results?.close()
            resized.recycle()
            letterboxed.recycle()
        }
    }

    private fun detectDocumentOpenCV(bitmap: Bitmap): MatOfPoint2f? {
        val src = Mat()
        val gray = Mat()
        val lab = Mat()
        val enhanced = Mat()
        val blurred = Mat()
        val edges = Mat()
        val contours = ArrayList<MatOfPoint>()
        
        try {
            Utils.bitmapToMat(bitmap, src)
            Imgproc.cvtColor(src, gray, Imgproc.COLOR_BGR2GRAY)
            
            val meanBrightness = Core.mean(gray).`val`[0]
            if (meanBrightness < 15.0) return null
            
            Imgproc.cvtColor(src, lab, Imgproc.COLOR_BGR2Lab)
            val labChannels = ArrayList<Mat>()
            Core.split(lab, labChannels)

            val clahe = Imgproc.createCLAHE()
            clahe.clipLimit = 3.0
            clahe.apply(labChannels[0], enhanced)

            Imgproc.GaussianBlur(enhanced, blurred, Size(5.0, 5.0), 0.0)

            Imgproc.adaptiveThreshold(blurred, edges, 255.0, Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C, Imgproc.THRESH_BINARY, 15, 10.0)
            
            Imgproc.findContours(edges, contours, Mat(), Imgproc.RETR_LIST, Imgproc.CHAIN_APPROX_SIMPLE)
            
            var bestScore = -1.0
            var bestApprox: MatOfPoint2f? = null

            val minArea = bitmap.width * bitmap.height * 0.15
            val maxArea = bitmap.width * bitmap.height * 0.95
            
            for (cnt in contours) {
                val peri = Imgproc.arcLength(MatOfPoint2f(*cnt.toArray()), true)
                val approx = MatOfPoint2f()
                Imgproc.approxPolyDP(MatOfPoint2f(*cnt.toArray()), approx, 0.02 * peri, true)
                
                if (approx.total() == 4L && Imgproc.isContourConvex(MatOfPoint(*approx.toArray()))) {
                    val area = Imgproc.contourArea(approx)
                    if (area > minArea && area < maxArea) {
                        val score = calculateScore(approx, edges, bitmap.width, bitmap.height)
                        if (score > bestScore) {
                            bestScore = score
                            // Need to clone bestApprox because approx will be released
                            bestApprox?.release()
                            bestApprox = MatOfPoint2f(*approx.toArray())
                        }
                    }
                }
                approx.release()
            }
            
            for (m in labChannels) m.release()
            return bestApprox
        } catch (e: Exception) {
            return null
        } finally {
            releaseMats(src, gray, lab, enhanced, blurred, edges)
            for (c in contours) c.release()
        }
    }

    private fun calculateScore(approx: MatOfPoint2f, edges: Mat, w: Int, h: Int): Double {
        var score = 0.0
        val pts = approx.toArray()
        val area = Imgproc.contourArea(approx)
        val maxArea = (w * h).toDouble()
        
        // 1. Area Size (Weight: 25)
        score += (area / maxArea) * 100.0 * 0.25

        // 2. Rectangle Angles (Weight: 25)
        // Check how close each corner is to 90 degrees
        var angleScore = 0.0
        for (i in 0..3) {
            val p1 = pts[i]
            val p2 = pts[(i + 1) % 4]
            val p3 = pts[(i + 2) % 4]
            val a = Math.toDegrees(Math.atan2(p1.y - p2.y, p1.x - p2.x) - Math.atan2(p3.y - p2.y, p3.x - p2.x))
            val diff = Math.abs(Math.abs(a) - 90.0)
            angleScore += Math.max(0.0, (22.5 - diff) / 22.5) // Grace range 22.5 degrees
        }
        score += (angleScore / 4.0) * 100.0 * 0.25

        // 3. Aspect Ratio (Weight: 10)
        // Favor A4 (1:1.41) or Letter (1:1.29)
        val rect = Imgproc.boundingRect(MatOfPoint(*pts))
        val ratio = if (rect.width > rect.height) rect.width.toDouble() / rect.height 
                    else rect.height.toDouble() / rect.width
        val ratioDiff = Math.abs(ratio - 1.41)
        score += Math.max(0.0, (1.0 - ratioDiff)) * 100.0 * 0.10

        // 4. Center Alignment (Weight: 10)
        val centerX = (pts[0].x + pts[1].x + pts[2].x + pts[3].x) / 4.0
        val centerY = (pts[0].y + pts[1].y + pts[2].y + pts[3].y) / 4.0
        val distToCenter = Math.hypot(centerX - w/2, centerY - h/2)
        val maxDist = Math.hypot(w/2.0, h/2.0)
        score += (1.0 - (distToCenter / maxDist)) * 100.0 * 0.10

        // 5. Edge Sharpness (Weight: 20)
        // Sample points along the edges in the Canny map
        var edgeHits = 0
        for (i in 0..3) {
            val p1 = pts[i]; val p2 = pts[(i + 1) % 4]
            for (step in 1..10) {
                val tx = p1.x + (p2.x - p1.x) * (step / 10.0)
                val ty = p1.y + (p2.y - p1.y) * (step / 10.0)
                if (tx >= 0 && tx < w && ty >= 0 && ty < h) {
                    if (edges.get(ty.toInt(), tx.toInt())[0] > 0) edgeHits++
                }
            }
        }
        score += (edgeHits / 40.0) * 100.0 * 0.20

        // 6. Convexity (Weight: 10) - Binary bonus
        if (Imgproc.isContourConvex(MatOfPoint(*pts))) score += 10.0

        return score
    }

    private fun detectDocumentHough(edges: Mat, width: Int, height: Int): MatOfPoint2f? {
        val lines = Mat()
        // HoughLinesP detects line segments
        Imgproc.HoughLinesP(edges, lines, 1.0, Math.PI / 180, 50, 50.0, 10.0)
        
        val horizontalLines = mutableListOf<DoubleArray>()
        val verticalLines = mutableListOf<DoubleArray>()

        for (i in 0 until lines.rows()) {
            val l = lines.get(i, 0)
            val dx = l[2] - l[0]
            val dy = l[3] - l[1]
            val angle = Math.abs(Math.atan2(dy, dx) * 180 / Math.PI)
            
            if (angle < 20 || angle > 160) horizontalLines.add(l)
            else if (angle > 70 && angle < 110) verticalLines.add(l)
        }

        if (horizontalLines.size < 2 || verticalLines.size < 2) return null

        // Find intersections to find potential corners
        val intersections = mutableListOf<Point>()
        for (h in horizontalLines) {
            for (v in verticalLines) {
                val p = findIntersection(h, v)
                if (p != null && p.x in 0.0..width.toDouble() && p.y in 0.0..height.toDouble()) {
                    intersections.add(p)
                }
            }
        }

        if (intersections.size < 4) return null

        // Group intersections into 4 corners (very simplified approach)
        val corners = Array(4) { Point() }
        corners[0] = intersections.minByOrNull { it.x + it.y }!! // TL
        corners[1] = intersections.maxByOrNull { it.x - it.y }!! // TR
        corners[2] = intersections.maxByOrNull { it.x + it.y }!! // BR
        corners[3] = intersections.minByOrNull { it.x - it.y }!! // BL

        return MatOfPoint2f(*corners)
    }

    private fun findIntersection(l1: DoubleArray, l2: DoubleArray): Point? {
        val x1 = l1[0]; val y1 = l1[1]; val x2 = l1[2]; val y2 = l1[3]
        val x3 = l2[0]; val y3 = l2[1]; val x4 = l2[2]; val y4 = l2[3]
        val denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
        if (denom == 0.0) return null
        val intersectX = ((x1 * y2 - y1 * x2) * (x3 - x4) - (x1 - x2) * (x3 * y4 - y3 * x4)) / denom
        val intersectY = ((x1 * y2 - y1 * x2) * (y3 - y4) - (y1 - y2) * (x3 * y4 - y3 * x4)) / denom
        return Point(intersectX, intersectY)
    }

    private fun warpDocument(bitmap: Bitmap, pts: MatOfPoint2f): Bitmap {
        val src = Mat()
        val warped = Mat()
        val rotated = Mat()
        val M = Mat()
        val dst = MatOfPoint2f()
        
        try {
            Utils.bitmapToMat(bitmap, src)
            val ordered = orderPoints(pts.toArray())
            val tl = ordered[0]; val tr = ordered[1]; val br = ordered[2]; val bl = ordered[3]
            
            var w = maxOf(Math.hypot(br.x - bl.x, br.y - bl.y), Math.hypot(tr.x - tl.x, tr.y - tl.y)).toInt()
            var h = maxOf(Math.hypot(tr.x - br.x, tr.y - br.y), Math.hypot(tl.x - bl.x, tl.y - bl.y)).toInt()
            
            if (w <= 0) w = 100
            if (h <= 0) h = 100

            dst.fromArray(
                Point(0.0, 0.0),
                Point(w - 1.0, 0.0),
                Point(w - 1.0, h - 1.0),
                Point(0.0, h - 1.0)
            )
            
            val transformM = Imgproc.getPerspectiveTransform(MatOfPoint2f(*ordered), dst)
            Imgproc.warpPerspective(src, warped, transformM, Size(w.toDouble(), h.toDouble()))
            transformM.release()
            
            var finalW = w
            var finalH = h
            val resultMat = if (w > h) {
                Core.rotate(warped, rotated, Core.ROTATE_90_CLOCKWISE)
                finalW = h
                finalH = w
                rotated
            } else {
                warped
            }

            val result = Bitmap.createBitmap(finalW, finalH, Bitmap.Config.ARGB_8888)
            Utils.matToBitmap(resultMat, result)
            return result
        } finally {
            releaseMats(src, warped, rotated, M, dst)
        }
    }

    private fun orderPoints(pts: Array<Point>): Array<Point> {
        if (pts.size != 4) return pts
        val ordered = Array(4) { Point() }
        
        // Use Sum and Difference method (more robust for skew)
        // TL: Min (x + y)
        // BR: Max (x + y)
        // TR: Min (y - x)
        // BL: Max (y - x)
        
        ordered[0] = pts.minBy { it.x + it.y } // TL
        ordered[2] = pts.maxBy { it.x + it.y } // BR
        
        val remaining = pts.filter { it != ordered[0] && it != ordered[2] }
        if (remaining.size == 2) {
            ordered[1] = remaining.minBy { it.y - it.x } // TR
            ordered[3] = remaining.maxBy { it.y - it.x } // BL
        } else {
            // Fallback for overlapping points
            ordered[1] = pts[1]; ordered[3] = pts[3]
        }
        
        return ordered
    }
}
