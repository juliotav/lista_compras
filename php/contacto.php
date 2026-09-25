<?php
// Configuración del correo de destino
$email_destino = "soporte@sonorodevs.com"; // <-- Modifica esto con tu correo electrónico real

$mensaje_estado = "";
$tipo_estado = ""; // 'success' o 'danger'

if ($_SERVER["REQUEST_METHOD"] === "POST") {
    // Verificación Anti-Spam (Honeypot)
    if (!empty($_POST["website_hp"])) {
        // Es un bot, simulamos respuesta exitosa
        $mensaje_estado = "¡Mensaje enviado con éxito! Nos pondremos en contacto contigo pronto.";
        $tipo_estado = "success";
    } else {
        // Sanitización e higiene de datos de entrada
        $nombre  = trim(filter_input(INPUT_POST, 'nombre', FILTER_SANITIZE_FULL_SPECIAL_CHARS));
        $email   = trim(filter_input(INPUT_POST, 'email', FILTER_SANITIZE_EMAIL));
        $asunto  = trim(filter_input(INPUT_POST, 'asunto', FILTER_SANITIZE_FULL_SPECIAL_CHARS));
        $mensaje = trim(filter_input(INPUT_POST, 'mensaje', FILTER_SANITIZE_FULL_SPECIAL_CHARS));

        // Validaciones
        if (empty($nombre) || empty($email) || empty($asunto) || empty($mensaje)) {
            $mensaje_estado = "Por favor completa todos los campos requeridos.";
            $tipo_estado = "danger";
        } elseif (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            $mensaje_estado = "Por favor ingresa un correo electrónico válido.";
            $tipo_estado = "danger";
        } else {
            // Limpieza del asunto para prevenir Header Injection
            $asunto_limpio = str_replace(array("\r", "\n"), '', $asunto);
            $subject = "Soporte App - " . ($asunto_limpio ? $asunto_limpio : "Consulta de Contacto");

            // Plantilla del mensaje en HTML
            $body = "
            <html>
            <head>
              <title>Nuevo mensaje de soporte</title>
              <style>
                body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
                .container { padding: 20px; border: 1px solid #e2e8f0; border-radius: 8px; background-color: #f8fafc; }
                .field { margin-bottom: 12px; }
                .label { font-weight: bold; color: #475569; }
                .content-box { background: #ffffff; padding: 15px; border-radius: 6px; border: 1px solid #cbd5e1; margin-top: 5px; }
                .footer { margin-top: 20px; font-size: 12px; color: #94a3b8; border-top: 1px solid #e2e8f0; padding-top: 10px; }
              </style>
            </head>
            <body>
              <div class='container'>
                <h2 style='color: #4f46e5; margin-top: 0;'>Nuevo Mensaje de Ayuda / Soporte</h2>
                <div class='field'><span class='label'>Nombre:</span> " . htmlspecialchars($nombre) . "</div>
                <div class='field'><span class='label'>Correo Electrónico:</span> <a href='mailto:" . htmlspecialchars($email) . "'>" . htmlspecialchars($email) . "</a></div>
                <div class='field'><span class='label'>Asunto / App:</span> " . htmlspecialchars($asunto) . "</div>
                <div class='field'>
                    <span class='label'>Mensaje:</span>
                    <div class='content-box'>" . nl2br(htmlspecialchars($mensaje)) . "</div>
                </div>
                <div class='footer'>Mensaje generado desde el sitio de contacto para Google Play Store.</div>
              </div>
            </body>
            </html>
            ";

            // Encabezados HTTP para el correo
            $headers  = "MIME-Version: 1.0" . "\r\n";
            $headers .= "Content-type: text/html; charset=UTF-8" . "\r\n";
            $headers .= "From: Soporte App <no-reply@" . ($_SERVER['HTTP_HOST'] ?? 'sonorodevs.com') . ">" . "\r\n";
            $headers .= "Reply-To: " . $email . "\r\n";

            // Envío utilizando la función nativa mail() de PHP
            if (@mail($email_destino, $subject, $body, $headers)) {
                $mensaje_estado = "¡Gracias por escribirnos! Tu mensaje ha sido enviado correctamente.";
                $tipo_estado = "success";
                // Limpiar campos del formulario tras envío exitoso
                $nombre = $email = $asunto = $mensaje = "";
            } else {
                $mensaje_estado = "Hubo un problema al enviar tu mensaje. Por favor revisa la configuración de correo de tu servidor o intenta más tarde.";
                $tipo_estado = "danger";
            }
        }
    }
}
?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Soporte y Ayuda - App</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <style>
        :root {
            --primary: #4F46E5;
            --primary-hover: #4338CA;
            --bg-gradient-start: #0F172A;
            --bg-gradient-end: #1E1B4B;
            --card-bg: rgba(255, 255, 255, 0.97);
            --text-dark: #1E293B;
            --text-muted: #64748B;
            --border-color: #CBD5E1;
            --focus-ring: rgba(79, 70, 229, 0.25);
            --radius: 16px;
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        body {
            font-family: 'Outfit', -apple-system, BlinkMacSystemFont, sans-serif;
            background: linear-gradient(135deg, var(--bg-gradient-start), var(--bg-gradient-end));
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 24px 16px;
            color: var(--text-dark);
        }

        .card {
            width: 100%;
            max-width: 520px;
            background: var(--card-bg);
            border-radius: var(--radius);
            box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.4);
            padding: 40px 32px;
        }

        .header {
            text-align: center;
            margin-bottom: 28px;
        }

        .header-icon {
            width: 56px;
            height: 56px;
            background: #EEF2FF;
            color: var(--primary);
            border-radius: 14px;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            margin-bottom: 16px;
        }

        .header-icon svg {
            width: 28px;
            height: 28px;
        }

        .header h1 {
            font-size: 1.65rem;
            font-weight: 700;
            color: var(--text-dark);
            margin-bottom: 8px;
            letter-spacing: -0.02em;
        }

        .header p {
            font-size: 0.925rem;
            color: var(--text-muted);
            line-height: 1.5;
        }

        .alert {
            padding: 14px 16px;
            border-radius: 10px;
            font-size: 0.9rem;
            font-weight: 500;
            margin-bottom: 24px;
            display: flex;
            align-items: center;
            gap: 10px;
        }

        .alert-success {
            background-color: #DEF7EC;
            color: #03543F;
            border: 1px solid #BCF0DA;
        }

        .alert-danger {
            background-color: #FDE8E8;
            color: #9B1C1C;
            border: 1px solid #FBD5D5;
        }

        .form-group {
            margin-bottom: 20px;
        }

        .form-group label {
            display: block;
            font-size: 0.875rem;
            font-weight: 600;
            color: #334155;
            margin-bottom: 6px;
        }

        .form-control {
            width: 100%;
            padding: 12px 16px;
            font-size: 0.95rem;
            font-family: inherit;
            border: 1.5px solid var(--border-color);
            border-radius: 10px;
            background-color: #F8FAFC;
            color: var(--text-dark);
            transition: all 0.2s ease;
        }

        .form-control:focus {
            outline: none;
            border-color: var(--primary);
            background-color: #FFFFFF;
            box-shadow: 0 0 0 4px var(--focus-ring);
        }

        textarea.form-control {
            resize: vertical;
            min-height: 120px;
        }

        .btn-submit {
            width: 100%;
            padding: 14px 20px;
            background: var(--primary);
            color: #FFFFFF;
            border: none;
            border-radius: 10px;
            font-size: 1rem;
            font-weight: 600;
            cursor: pointer;
            transition: background 0.2s ease, transform 0.1s ease;
            box-shadow: 0 4px 12px rgba(79, 70, 229, 0.3);
        }

        .btn-submit:hover {
            background: var(--primary-hover);
        }

        .btn-submit:active {
            transform: scale(0.99);
        }

        .divider {
            height: 1px;
            background: #E2E8F0;
            margin: 32px 0 24px;
        }

        .corporate-section {
            text-align: center;
        }

        .corporate-section p {
            font-size: 0.875rem;
            color: var(--text-muted);
            margin-bottom: 12px;
        }

        .corporate-btn {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            color: var(--primary);
            font-weight: 600;
            font-size: 0.925rem;
            text-decoration: none;
            padding: 10px 20px;
            background: #F1F5F9;
            border-radius: 30px;
            transition: all 0.2s ease;
        }

        .corporate-btn:hover {
            background: #E2E8F0;
            color: var(--primary-hover);
            transform: translateY(-1px);
        }

        .corporate-btn svg {
            width: 16px;
            height: 16px;
            transition: transform 0.2s ease;
        }

        .corporate-btn:hover svg {
            transform: translateX(3px);
        }

        /* Anti-Spam Honeypot Field */
        .hp-field {
            display: none !important;
            visibility: hidden !important;
        }
    </style>
</head>
<body>

    <div class="card">
        <div class="header">
            <div class="header-icon">
                <svg fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18.364 5.636l-3.536 3.536m0 5.656l3.536 3.536M9.172 9.172L5.636 5.636m3.536 9.192l-3.536 3.536M21 12a9 9 0 11-18 0 9 9 0 0118 0zm-5 0a4 4 0 11-8 0 4 4 0 018 0z"></path>
                </svg>
            </div>
            <h1>Centro de Soporte</h1>
            <p>¿Necesitas ayuda con nuestra aplicación? Envíanos tus dudas o comentarios y te responderemos a la brevedad.</p>
        </div>

        <?php if (!empty($mensaje_estado)): ?>
            <div class="alert alert-<?php echo $tipo_estado; ?>">
                <?php if ($tipo_estado === 'success'): ?>
                    <svg style="width:20px;height:20px;flex-shrink:0;" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path></svg>
                <?php else: ?>
                    <svg style="width:20px;height:20px;flex-shrink:0;" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>
                <?php endif; ?>
                <span><?php echo $mensaje_estado; ?></span>
            </div>
        <?php endif; ?>

        <form action="<?php echo htmlspecialchars($_SERVER["PHP_SELF"]); ?>" method="POST">
            <!-- Campo de seguridad Anti-Spam oculto -->
            <input type="text" name="website_hp" class="hp-field" tabindex="-1" autocomplete="off">

            <div class="form-group">
                <label for="nombre">Nombre completo</label>
                <input type="text" id="nombre" name="nombre" class="form-control" placeholder="Tu nombre" required value="<?php echo isset($nombre) ? htmlspecialchars($nombre) : ''; ?>">
            </div>

            <div class="form-group">
                <label for="email">Correo electrónico</label>
                <input type="email" id="email" name="email" class="form-control" placeholder="tu@correo.com" required value="<?php echo isset($email) ? htmlspecialchars($email) : ''; ?>">
            </div>

            <div class="form-group">
                <label for="asunto">Nombre de la App / Asunto</label>
                <input type="text" id="asunto" name="asunto" class="form-control" placeholder="Ej. Duda sobre la app / Reporte de falla" required value="<?php echo isset($asunto) ? htmlspecialchars($asunto) : ''; ?>">
            </div>

            <div class="form-group">
                <label for="mensaje">Mensaje</label>
                <textarea id="mensaje" name="mensaje" class="form-control" placeholder="Describe brevemente en qué podemos ayudarte..." required><?php echo isset($mensaje) ? htmlspecialchars($mensaje) : ''; ?></textarea>
            </div>

            <button type="submit" class="btn-submit">Enviar mensaje</button>
        </form>

        <div class="divider"></div>

        <div class="corporate-section">
            <p>Desarrollado por la firma tecnológica</p>
            <a href="https://sonorodevs.com" target="_blank" rel="noopener noreferrer" class="corporate-btn">
                <span>Visitar Sonoro Devs</span>
                <svg fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14 5l7 7m0 0l-7 7m7-7H3"></path>
                </svg>
            </a>
        </div>
    </div>

</body>
</html>
