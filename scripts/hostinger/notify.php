<?php
/**
 * Microservicio PHP para envío de Notificaciones Push vía Firebase Cloud Messaging (FCM API v1)
 * Diseñado para Hostinger (PHP 7.4 / 8.x) - 100% nativo sin dependencias de Composer.
 * 
 * Instrucciones:
 * 1. Sube este archivo a tu servidor Hostinger (ejemplo: public_html/api/notification/notify.php).
 * 2. Coloca tu archivo 'service-account.json' (descargado desde Firebase Console) en el mismo directorio.
 * 3. Configura la misma clave secreta en $appSecret y en NOTIFICATION_APP_SECRET de tu app Flutter.
 */

header('Content-Type: application/json; charset=utf-8');

// Clave secreta compartida para autorizar las peticiones desde la App Móvil
define('APP_SECRET', 'sonorodevs_push_secret_key_2026');

// Ruta al archivo de credenciales de Firebase Service Account
define('SERVICE_ACCOUNT_PATH', __DIR__ . '/service-account.json');

// 1. Validar método HTTP POST
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'Method Not Allowed. Use POST.']);
    exit;
}

// 2. Validar Cabecera de Seguridad X-App-Secret
$headers = getallheaders();
$receivedSecret = isset($headers['X-App-Secret']) ? $headers['X-App-Secret'] : (isset($headers['x-app-secret']) ? $headers['x-app-secret'] : '');

if ($receivedSecret !== APP_SECRET) {
    http_response_code(401);
    echo json_encode(['error' => 'Unauthorized. Invalid X-App-Secret.']);
    exit;
}

// 3. Leer y parsear el cuerpo JSON de la petición
$rawInput = file_get_contents('php://input');
$data = json_decode($rawInput, true);

if (!$data || empty($data['id_familia']) || empty($data['body'])) {
    http_response_code(400);
    echo json_encode(['error' => 'Bad Request. Missing required fields (id_familia, body).']);
    exit;
}

$idFamilia    = trim($data['id_familia']);
$title        = isset($data['title']) ? trim($data['title']) : 'Lista de Compras';
$body         = trim($data['body']);
$idLista      = isset($data['id_lista']) ? trim($data['id_lista']) : '';
$nbLista      = isset($data['nb_lista']) ? trim($data['nb_lista']) : '';
$senderUserId = isset($data['sender_user_id']) ? trim($data['sender_user_id']) : '';

// 4. Verificar existencia de credenciales de Firebase
if (!file_exists(SERVICE_ACCOUNT_PATH)) {
    http_response_code(500);
    echo json_encode(['error' => 'Firebase credentials file (service-account.json) not found on server.']);
    exit;
}

$serviceAccount = json_decode(file_get_contents(SERVICE_ACCOUNT_PATH), true);
if (!$serviceAccount || empty($serviceAccount['client_email']) || empty($serviceAccount['private_key']) || empty($serviceAccount['project_id'])) {
    http_response_code(500);
    echo json_encode(['error' => 'Invalid service-account.json format.']);
    exit;
}

/**
 * Genera un token de acceso OAuth2 de Google mediante firma JWT con OpenSSL
 */
function getGoogleAccessToken($serviceAccount) {
    $now = time();
    $jwtHeader = json_encode(['alg' => 'RS256', 'typ' => 'JWT']);
    $jwtClaim = json_encode([
        'iss' => $serviceAccount['client_email'],
        'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
        'aud' => 'https://oauth2.googleapis.com/token',
        'exp' => $now + 3600,
        'iat' => $now
    ]);

    $base64Header = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($jwtHeader));
    $base64Claim = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($jwtClaim));

    $signatureInput = $base64Header . '.' . $base64Claim;
    $privateKey = openssl_pkey_get_private($serviceAccount['private_key']);
    
    if (!$privateKey) {
        return false;
    }

    openssl_sign($signatureInput, $signature, $privateKey, OPENSSL_ALGO_SHA256);
    $base64Signature = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($signature));

    $jwt = $signatureInput . '.' . $base64Signature;

    // Solicitar Access Token a Google OAuth2
    $ch = curl_init('https://oauth2.googleapis.com/token');
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query([
        'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion' => $jwt
    ]));
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/x-www-form-urlencoded']);

    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($httpCode === 200) {
        $tokenData = json_decode($response, true);
        return isset($tokenData['access_token']) ? $tokenData['access_token'] : false;
    }

    return false;
}

$accessToken = getGoogleAccessToken($serviceAccount);
if (!$accessToken) {
    http_response_code(500);
    echo json_encode(['error' => 'Failed to obtain Google OAuth2 access token.']);
    exit;
}

// 5. Construir mensaje FCM v1 para el topic familiar
$fcmUrl = 'https://fcm.googleapis.com/v1/projects/' . $serviceAccount['project_id'] . '/messages:send';

$messagePayload = [
    'message' => [
        'topic' => 'family_' . $idFamilia,
        'notification' => [
            'title' => $title,
            'body' => $body
        ],
        'data' => [
            'id_familia' => (string)$idFamilia,
            'id_lista' => (string)$idLista,
            'nb_lista' => (string)$nbLista,
            'sender_user_id' => (string)$senderUserId,
            'click_action' => 'FLUTTER_NOTIFICATION_CLICK'
        ],
        'android' => [
            'priority' => 'high',
            'notification' => [
                'sound' => 'default',
                'channel_id' => 'high_importance_channel',
                'click_action' => 'FLUTTER_NOTIFICATION_CLICK',
                'default_sound' => true,
                'default_vibrate_timings' => true
            ]
        ],
        'apns' => [
            'payload' => [
                'aps' => [
                    'sound' => 'default',
                    'badge' => 1
                ]
            ]
        ]
    ]
];

// 6. Enviar mensaje a Firebase FCM
$ch = curl_init($fcmUrl);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($messagePayload));
curl_setopt($ch, CURLOPT_HTTPHEADER, [
    'Authorization: Bearer ' . $accessToken,
    'Content-Type: application/json; UTF-8'
]);

$fcmResponse = curl_exec($ch);
$fcmStatus = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

if ($fcmStatus === 200) {
    echo json_encode([
        'success' => true,
        'message' => 'Notification dispatched successfully to family topic.',
        'fcm_response' => json_decode($fcmResponse, true)
    ]);
} else {
    http_response_code($fcmStatus);
    echo json_encode([
        'success' => false,
        'error' => 'FCM API returned error.',
        'status_code' => $fcmStatus,
        'fcm_response' => json_decode($fcmResponse, true)
    ]);
}
