package byd

import android.content.Context
import android.os.StrictMode
import android.util.Base64
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.EOFException
import java.io.File
import java.math.BigInteger
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.StandardCharsets
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.interfaces.RSAPublicKey
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.util.concurrent.atomic.AtomicInteger
import javax.crypto.Cipher
import kotlin.math.min

/**
 * Tiny classic ADB-over-TCP client.
 *
 * This is intentionally scoped to the one thing the launcher needs: connect to
 * a local adbd, trigger Android's "Allow USB debugging" prompt via RSA auth,
 * then run shell commands as uid=2000(shell).
 */
object LocalAdbClient {
    private const val DEFAULT_HOST = "127.0.0.1"
    private const val DEFAULT_PORT = 5555
    private const val CONNECT_TIMEOUT_MS = 8_000
    private const val AUTH_TIMEOUT_MS = 5_000
    private const val SHELL_TIMEOUT_MS = 12_000
    private const val ADB_VERSION = 0x01000000
    private const val MAX_DATA = 4096

    private val nextLocalId = AtomicInteger(1)

    fun runShellCommand(
        context: Context,
        command: String,
        host: String = DEFAULT_HOST,
        port: Int = DEFAULT_PORT,
    ): AdbShellResult {
        val oldPolicy = StrictMode.getThreadPolicy()
        var socket: Socket? = null
        var stage = "connecting"
        return try {
            StrictMode.setThreadPolicy(StrictMode.ThreadPolicy.Builder(oldPolicy).permitNetwork().build())
            socket = connectAndAuthorize(
                context = context,
                host = host,
                port = port,
                onStage = { stage = it },
            )
            stage = "running_shell"
            runShell(socket, command)
        } catch (error: Throwable) {
            AdbShellResult(
                command = command,
                started = false,
                exitCode = -1,
                output = "stage=$stage ${error.javaClass.simpleName}: ${error.message.orEmpty()}".take(4000),
            )
        } finally {
            StrictMode.setThreadPolicy(oldPolicy)
            try {
                socket?.close()
            } catch (_: Throwable) {
            }
        }
    }

    fun runShellCommandWithCandidates(
        context: Context,
        command: String,
        port: Int = DEFAULT_PORT,
    ): AdbShellResult {
        val hosts = candidateHosts()
        val attempts = mutableListOf<String>()
        for (host in hosts) {
            val result = runShellCommand(context, command, host, port)
            if (result.started) {
                return result.copy(output = "[adbHost=$host]\n${result.output}".trim())
            }
            attempts += "$host -> ${result.output}"
        }
        return AdbShellResult(
            command = command,
            started = false,
            exitCode = -1,
            output = attempts.joinToString("\n").take(4000),
        )
    }

    fun runShellCommandsInteractiveWithCandidates(
        context: Context,
        commands: List<String>,
        port: Int = DEFAULT_PORT,
    ): AdbShellBatchResult {
        val hosts = candidateHosts()
        val attempts = mutableListOf<String>()
        for (host in hosts) {
            val result = runShellCommandsInteractive(context, commands, host, port)
            if (result.started) {
                return result.copy(host = host)
            }
            attempts += "$host -> ${result.error.orEmpty()}"
        }
        return AdbShellBatchResult(
            host = hosts.firstOrNull().orEmpty(),
            started = false,
            results = commands.take(1).map {
                AdbShellResult(
                    command = it,
                    started = false,
                    exitCode = -1,
                    output = attempts.joinToString("\n").take(4000),
                )
            },
            error = attempts.joinToString("\n").take(4000),
        )
    }

    private fun runShellCommandsInteractive(
        context: Context,
        commands: List<String>,
        host: String,
        port: Int,
    ): AdbShellBatchResult {
        val oldPolicy = StrictMode.getThreadPolicy()
        var socket: Socket? = null
        var stage = "connecting"
        return try {
            StrictMode.setThreadPolicy(StrictMode.ThreadPolicy.Builder(oldPolicy).permitNetwork().build())
            socket = connectAndAuthorize(
                context = context,
                host = host,
                port = port,
                onStage = { stage = it },
            )
            stage = "open_interactive_shell"
            val session = openInteractiveShell(context, socket)
            val results = commands.map { command ->
                stage = "run_interactive_command"
                session.runCommand(command)
            }
            try {
                session.close()
            } catch (_: Throwable) {
            }
            AdbShellBatchResult(
                host = host,
                started = true,
                results = results,
                error = null,
            )
        } catch (error: Throwable) {
            AdbShellBatchResult(
                host = host,
                started = false,
                results = commands.take(1).map {
                    AdbShellResult(
                        command = it,
                        started = false,
                        exitCode = -1,
                        output = "stage=$stage ${error.javaClass.simpleName}: ${error.message.orEmpty()}".take(4000),
                    )
                },
                error = "stage=$stage ${error.javaClass.simpleName}: ${error.message.orEmpty()}".take(4000),
            )
        } finally {
            StrictMode.setThreadPolicy(oldPolicy)
            try {
                socket?.close()
            } catch (_: Throwable) {
            }
        }
    }

    private fun candidateHosts(): List<String> {
        val hosts = linkedSetOf(DEFAULT_HOST, "localhost")
        try {
            NetworkInterface.getNetworkInterfaces().toList()
                .filter { it.isUp && !it.isLoopback }
                .flatMap { it.inetAddresses.toList() }
                .map { it.hostAddress.orEmpty().substringBefore("%") }
                .filter { it.isNotBlank() && !it.contains(":") }
                .forEach { hosts += it }
        } catch (_: Throwable) {
        }
        return hosts.toList()
    }

    private fun connectAndAuthorize(
        context: Context,
        host: String,
        port: Int,
        onStage: (String) -> Unit,
    ): Socket {
        val socket = Socket()
        onStage("socket_connect")
        socket.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)
        socket.soTimeout = AUTH_TIMEOUT_MS
        onStage("send_cnxn")
        FileLogger.log(context, "LocalAdbClient connected to $host:$port; sending CNXN")

        val keyMaterial = AdbKeyStore.getOrCreate(context)
        FileLogger.log(context, "LocalAdbClient using ADB key source=${keyMaterial.source}")
        writePacket(socket, Command.CNXN, ADB_VERSION, MAX_DATA, "host::".adbPayload())

        var signedOnce = false
        while (true) {
            onStage("read_auth_packet")
            val packet = readPacket(socket)
            FileLogger.log(
                context,
                "LocalAdbClient auth packet ${commandName(packet.command)} arg0=${packet.arg0} arg1=${packet.arg1} payload=${packet.payload.size}"
            )
            when (packet.command) {
                Command.CNXN -> {
                    FileLogger.log(context, "LocalAdbClient authorized on $host:$port")
                    socket.soTimeout = SHELL_TIMEOUT_MS
                    return socket
                }

                Command.AUTH -> {
                    when (packet.arg0) {
                        AuthType.TOKEN -> {
                            if (!signedOnce) {
                                signedOnce = true
                                val signature = signToken(keyMaterial.privateKey, packet.payload)
                                onStage("send_signature")
                                FileLogger.log(context, "LocalAdbClient sending AUTH signature to $host:$port")
                                writePacket(socket, Command.AUTH, AuthType.SIGNATURE, 0, signature)
                            } else {
                                onStage("send_public_key")
                                FileLogger.log(context, "LocalAdbClient sending AUTH public key to $host:$port")
                                val publicKeyPayload = keyMaterial.adbPublicKeyPayload
                                AdbKeyStore.writeAdbPublicKey(context, publicKeyPayload)
                                writePacket(
                                    socket,
                                    Command.AUTH,
                                    AuthType.RSAPUBLICKEY,
                                    0,
                                    publicKeyPayload,
                                )
                            }
                        }

                        else -> throw IllegalStateException("Unsupported ADB AUTH type ${packet.arg0}")
                    }
                }

                else -> throw IllegalStateException("Unexpected ADB packet during auth: ${packet.command}")
            }
        }
    }

    private fun runShell(socket: Socket, command: String): AdbShellResult {
        val marker = "__BYD_ADB_EXIT__"
        val wrapped = "$command; echo $marker:\$?"
        val localId = nextLocalId.getAndIncrement()
        var remoteId = 0
        val output = ByteArrayOutputStream()

        writePacket(socket, Command.OPEN, localId, 0, "shell:$wrapped".adbPayload())

        while (true) {
            val packet = readPacket(socket)
            when (packet.command) {
                Command.OKAY -> {
                    if (packet.arg1 == localId) {
                        remoteId = packet.arg0
                    }
                }

                Command.WRTE -> {
                    if (remoteId == 0) remoteId = packet.arg0
                    output.write(packet.payload)
                    writePacket(socket, Command.OKAY, localId, remoteId, ByteArray(0))
                }

                Command.CLSE -> {
                    writePacket(socket, Command.CLSE, localId, remoteId, ByteArray(0))
                    val text = output.toString(StandardCharsets.UTF_8.name()).trim()
                    val exitCode = parseExitCode(text, marker)
                    return AdbShellResult(
                        command = command,
                        started = true,
                        exitCode = exitCode,
                        output = stripExitMarker(text, marker).take(4000),
                    )
                }

                else -> {
                    // Ignore unrelated connection packets; this client opens one shell stream at a time.
                }
            }
        }
    }

    private fun openInteractiveShell(context: Context, socket: Socket): AdbInteractiveShell {
        val localId = nextLocalId.getAndIncrement()
        var remoteId = 0
        val initial = StringBuilder()

        FileLogger.log(context, "LocalAdbClient opening interactive shell:")
        writePacket(socket, Command.OPEN, localId, 0, "shell:".adbPayload())

        val deadline = System.currentTimeMillis() + 25_000
        while (System.currentTimeMillis() < deadline) {
            val packet = readPacket(socket)
            when (packet.command) {
                Command.OKAY -> {
                    if (packet.arg1 == localId) {
                        remoteId = packet.arg0
                    }
                }

                Command.WRTE -> {
                    if (remoteId == 0) remoteId = packet.arg0
                    initial.append(packet.payload.toString(StandardCharsets.UTF_8))
                    writePacket(socket, Command.OKAY, localId, remoteId, ByteArray(0))
                    if (looksLikePrompt(initial.toString())) {
                        FileLogger.log(context, "LocalAdbClient interactive shell prompt ready")
                        return AdbInteractiveShell(socket, localId, remoteId, initial)
                    }
                }

                Command.CLSE -> throw EOFException("Interactive shell closed before prompt")
            }
        }

        // Some BYD shells do not print a prompt until the first newline.
        if (remoteId != 0) {
            writePacket(socket, Command.WRTE, localId, remoteId, "\n".toByteArray(StandardCharsets.UTF_8))
            return AdbInteractiveShell(socket, localId, remoteId, initial)
        }
        throw EOFException("Interactive shell prompt timeout")
    }

    private class AdbInteractiveShell(
        private val socket: Socket,
        private val localId: Int,
        private val remoteId: Int,
        initialOutput: StringBuilder,
    ) {
        private val buffer = StringBuilder(initialOutput)

        fun runCommand(command: String): AdbShellResult {
            val marker = "__BYD_ADB_EXIT_${System.nanoTime()}__"
            val start = buffer.length
            writeLine("$command; echo $marker:\$?")
            val text = readUntilMarker(marker, start).trim()
            val exitCode = parseExitCode(text, marker)
            return AdbShellResult(
                command = command,
                started = true,
                exitCode = exitCode,
                output = stripExitMarker(text, marker).take(4000),
            )
        }

        fun close() {
            writeLine("exit")
            writePacket(socket, Command.CLSE, localId, remoteId, ByteArray(0))
        }

        private fun writeLine(line: String) {
            writePacket(
                socket,
                Command.WRTE,
                localId,
                remoteId,
                (line + "\n").toByteArray(StandardCharsets.UTF_8),
            )
        }

        private fun readUntilMarker(marker: String, start: Int): String {
            val deadline = System.currentTimeMillis() + 25_000
            while (System.currentTimeMillis() < deadline) {
                val current = buffer.substring(start)
                if (current.lineSequence().any { it.trimStart().startsWith("$marker:") }) {
                    return current
                }
                val packet = readPacket(socket)
                when (packet.command) {
                    Command.OKAY -> {
                        // ACK for a WRTE sent by us.
                    }

                    Command.WRTE -> {
                        buffer.append(packet.payload.toString(StandardCharsets.UTF_8))
                        writePacket(socket, Command.OKAY, localId, remoteId, ByteArray(0))
                    }

                    Command.CLSE -> throw EOFException("Interactive shell closed while waiting for command output")
                }
            }
            throw EOFException("Interactive shell command timeout for marker $marker")
        }
    }

    private fun looksLikePrompt(text: String): Boolean {
        val trimmed = text.replace("\r\n", "\n").trimEnd()
        return trimmed.endsWith("$") ||
            trimmed.endsWith("#") ||
            trimmed.lineSequence().lastOrNull()?.matches(Regex(".*[#$]\\s*$")) == true
    }

    private fun signToken(privateKey: PrivateKey, token: ByteArray): ByteArray {
        val sha1DigestInfoPrefix = byteArrayOf(
            0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e,
            0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14,
        )
        val digestInfo = sha1DigestInfoPrefix + token
        val cipher = Cipher.getInstance("RSA/ECB/PKCS1Padding")
        cipher.init(Cipher.ENCRYPT_MODE, privateKey)
        return cipher.doFinal(digestInfo)
    }

    private fun parseExitCode(text: String, marker: String): Int {
        val line = text.lineSequence().lastOrNull { it.startsWith("$marker:") }
        return line?.substringAfter(":")?.trim()?.toIntOrNull() ?: 0
    }

    private fun stripExitMarker(text: String, marker: String): String =
        text.lineSequence()
            .filterNot { it.startsWith("$marker:") }
            .joinToString("\n")
            .trim()

    private fun writePacket(
        socket: Socket,
        command: Int,
        arg0: Int,
        arg1: Int,
        payload: ByteArray,
    ) {
        val checksum = payload.fold(0) { sum, byte -> sum + (byte.toInt() and 0xff) }
        val header = ByteBuffer.allocate(24).order(ByteOrder.LITTLE_ENDIAN)
            .putInt(command)
            .putInt(arg0)
            .putInt(arg1)
            .putInt(payload.size)
            .putInt(checksum)
            .putInt(command xor -1)
            .array()
        socket.getOutputStream().write(header)
        if (payload.isNotEmpty()) {
            socket.getOutputStream().write(payload)
        }
        socket.getOutputStream().flush()
    }

    private fun readPacket(socket: Socket): AdbPacket {
        val header = ByteArray(24)
        DataInputStream(socket.getInputStream()).readFully(header)
        val buffer = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
        val command = buffer.int
        val arg0 = buffer.int
        val arg1 = buffer.int
        val length = buffer.int
        val checksum = buffer.int
        val magic = buffer.int
        if (magic != (command xor -1)) {
            throw EOFException("Invalid ADB packet magic")
        }
        val payload = ByteArray(length)
        if (length > 0) {
            DataInputStream(socket.getInputStream()).readFully(payload)
            val actual = payload.fold(0) { sum, byte -> sum + (byte.toInt() and 0xff) }
            if (actual != checksum) {
                throw EOFException("Invalid ADB packet checksum")
            }
        }
        return AdbPacket(command, arg0, arg1, payload)
    }

    private fun String.adbPayload(): ByteArray =
        (this + "\u0000").toByteArray(StandardCharsets.UTF_8)

    private object Command {
        val AUTH = adbCommand("AUTH")
        val CLSE = adbCommand("CLSE")
        val CNXN = adbCommand("CNXN")
        val OKAY = adbCommand("OKAY")
        val OPEN = adbCommand("OPEN")
        val WRTE = adbCommand("WRTE")
    }

    private fun commandName(command: Int): String {
        val bytes = byteArrayOf(
            (command and 0xff).toByte(),
            ((command shr 8) and 0xff).toByte(),
            ((command shr 16) and 0xff).toByte(),
            ((command shr 24) and 0xff).toByte(),
        )
        return String(bytes, StandardCharsets.US_ASCII)
    }

    private object AuthType {
        const val TOKEN = 1
        const val SIGNATURE = 2
        const val RSAPUBLICKEY = 3
    }

    private fun adbCommand(value: String): Int {
        val bytes = value.toByteArray(StandardCharsets.US_ASCII)
        return (bytes[0].toInt() and 0xff) or
            ((bytes[1].toInt() and 0xff) shl 8) or
            ((bytes[2].toInt() and 0xff) shl 16) or
            ((bytes[3].toInt() and 0xff) shl 24)
    }

    private data class AdbPacket(
        val command: Int,
        val arg0: Int,
        val arg1: Int,
        val payload: ByteArray,
    )

    data class AdbShellResult(
        val command: String,
        val started: Boolean,
        val exitCode: Int,
        val output: String,
    )

    data class AdbShellBatchResult(
        val host: String,
        val started: Boolean,
        val results: List<AdbShellResult>,
        val error: String?,
    )

    private data class AdbKeyMaterial(
        val privateKey: PrivateKey,
        val publicKey: RSAPublicKey?,
        val adbPublicKeyPayload: ByteArray,
        val source: String,
    )

    private object AdbKeyStore {
        private const val PRIVATE_KEY_FILE = "kinex_adb_private.pk8"
        private const val PUBLIC_KEY_FILE = "kinex_adb_public.der"
        private const val ADB_PUBLIC_KEY_FILE = "kinex_adb_public.adb_key"
        private const val DEV_PRIVATE_KEY_FILE = "dev_adb_private.pk8"
        private const val DEV_ADB_PUBLIC_KEY_FILE = "dev_adb_public.adb_key"

        fun getOrCreate(context: Context): AdbKeyMaterial {
            loadDevKey(context)?.let { return it }

            val privateFile = File(context.filesDir, PRIVATE_KEY_FILE)
            val publicFile = File(context.filesDir, PUBLIC_KEY_FILE)
            if (privateFile.exists() && publicFile.exists()) {
                val factory = KeyFactory.getInstance("RSA")
                val privateKey = factory.generatePrivate(PKCS8EncodedKeySpec(privateFile.readBytes()))
                val publicKey = factory.generatePublic(X509EncodedKeySpec(publicFile.readBytes())) as RSAPublicKey
                return AdbKeyMaterial(
                    privateKey = privateKey,
                    publicKey = publicKey,
                    adbPublicKeyPayload = encodeAdbPublicKey(publicKey),
                    source = "app_generated",
                )
            }

            val generator = KeyPairGenerator.getInstance("RSA")
            generator.initialize(2048)
            val pair = generator.generateKeyPair()
            privateFile.writeBytes(pair.private.encoded)
            publicFile.writeBytes(pair.public.encoded)
            val publicKey = pair.public as RSAPublicKey
            return AdbKeyMaterial(
                privateKey = pair.private,
                publicKey = publicKey,
                adbPublicKeyPayload = encodeAdbPublicKey(publicKey),
                source = "app_generated_new",
            )
        }

        fun writeAdbPublicKey(context: Context, encoded: ByteArray) {
            try {
                File(context.filesDir, ADB_PUBLIC_KEY_FILE).writeBytes(encoded)
                val logDir = File(context.getExternalFilesDir(null), "logs")
                if (!logDir.exists()) logDir.mkdirs()
                File(logDir, ADB_PUBLIC_KEY_FILE).writeBytes(encoded)
            } catch (_: Throwable) {
            }
        }

        private fun loadDevKey(context: Context): AdbKeyMaterial? {
            return try {
                val logDir = File(context.getExternalFilesDir(null), "logs")
                val privateFile = File(logDir, DEV_PRIVATE_KEY_FILE)
                val publicFile = File(logDir, DEV_ADB_PUBLIC_KEY_FILE)
                if (!privateFile.exists() || !publicFile.exists()) return null

                val factory = KeyFactory.getInstance("RSA")
                val privateKey = factory.generatePrivate(PKCS8EncodedKeySpec(privateFile.readBytes()))
                val publicPayload = normalizeAdbPublicKeyPayload(publicFile.readBytes())
                FileLogger.log(context, "LocalAdbClient imported dev ADB key from ${logDir.absolutePath}")
                AdbKeyMaterial(
                    privateKey = privateKey,
                    publicKey = null,
                    adbPublicKeyPayload = publicPayload,
                    source = "dev_imported",
                )
            } catch (error: Throwable) {
                FileLogger.log(
                    context,
                    "LocalAdbClient dev ADB key import failed: ${error.javaClass.simpleName}: ${error.message.orEmpty()}"
                )
                null
            }
        }

        private fun normalizeAdbPublicKeyPayload(bytes: ByteArray): ByteArray {
            val text = bytes.toString(StandardCharsets.UTF_8)
                .trim { it == '\u0000' || it == '\r' || it == '\n' || it == ' ' || it == '\t' }
            return "$text\u0000".toByteArray(StandardCharsets.UTF_8)
        }
    }

    private fun encodeAdbPublicKey(publicKey: RSAPublicKey): ByteArray {
        val modulus = publicKey.modulus
        val exponent = publicKey.publicExponent.toInt()
        val r32 = BigInteger.ONE.shiftLeft(32)
        val r = BigInteger.ONE.shiftLeft(2048)
        val rr = r.multiply(r).mod(modulus)
        val n0 = modulus.mod(r32)
        val n0inv = r32.subtract(n0.modInverse(r32)).and(BigInteger("ffffffff", 16)).toLong()

        val raw = ByteBuffer.allocate(4 + 4 + 256 + 256 + 4).order(ByteOrder.LITTLE_ENDIAN)
        raw.putInt(64)
        raw.putInt(n0inv.toInt())
        raw.putLittleEndianWords(modulus, 64)
        raw.putLittleEndianWords(rr, 64)
        raw.putInt(exponent)

        val encoded = Base64.encodeToString(raw.array(), Base64.NO_WRAP)
        return "$encoded byd_launcher@android\u0000".toByteArray(StandardCharsets.UTF_8)
    }

    private fun ByteBuffer.putLittleEndianWords(value: BigInteger, wordCount: Int) {
        val bytes = value.toByteArray()
        val positive = if (bytes.isNotEmpty() && bytes[0].toInt() == 0) {
            bytes.copyOfRange(1, bytes.size)
        } else {
            bytes
        }
        val little = ByteArray(wordCount * 4)
        for (i in positive.indices) {
            if (i < little.size) {
                little[i] = positive[positive.size - 1 - i]
            }
        }

        for (word in 0 until wordCount) {
            val offset = word * 4
            val chunk = min(4, little.size - offset)
            var intValue = 0
            for (i in 0 until chunk) {
                intValue = intValue or ((little[offset + i].toInt() and 0xff) shl (i * 8))
            }
            putInt(intValue)
        }
    }
}
