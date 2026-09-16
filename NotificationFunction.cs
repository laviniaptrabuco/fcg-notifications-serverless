using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;

namespace FcgNotificationsServerless;

/// <summary>
/// Substitui o container NotificationsAPI (que rodava 24/7 esperando eventos)
/// por uma Azure Function acionada diretamente pela fila RabbitMQ
/// "PaymentProcessed" - a mesma fila que o payments-api ja publica via
/// MassTransit (ver fcg-payments-api/src/FCG.PaymentsAPI/Consumers/
/// OrderPlacedConsumer.cs). Nao existe binding de trigger oficial da
/// Microsoft para RabbitMQ no modelo isolated worker; o pacote
/// Microsoft.Azure.WebJobs.Extensions.RabbitMQ (usado aqui) exige o
/// modelo "in-process" classico, que ainda e totalmente suportado no
/// Azure Functions v4.
/// </summary>
public static class NotificationFunction
{
    /// <summary>
    /// [RabbitMQTrigger] é um trigger de verdade: o runtime do Azure
    /// Functions se inscreve como consumidor da fila via AMQP e invoca esta
    /// função a cada mensagem publicada — não é polling.
    ///
    /// A mensagem chega no formato de envelope do MassTransit (JSON com
    /// metadados de correlação + o payload em "message"), por isso o
    /// parsing usa JObject em vez de desserializar direto para um tipo.
    /// </summary>
    [FunctionName("PaymentProcessedNotification")]
    public static void Run(
        [RabbitMQTrigger("PaymentProcessed", ConnectionStringSetting = "RabbitMQConnection")] string messageBody,
        ILogger log)
    {
        log.LogInformation("Mensagem recebida na fila PaymentProcessed");

        JObject envelope;
        try
        {
            envelope = JObject.Parse(messageBody);
        }
        catch (Exception ex)
        {
            log.LogError(ex, "Payload nao e um JSON valido, descartando mensagem: {Body}", messageBody);
            return;
        }

        // Envelope padrao do MassTransit: o payload real do evento fica
        // dentro do campo "message".
        var payload = envelope["message"] ?? envelope;

        var orderId = payload.Value<string>("orderId") ?? payload.Value<string>("OrderId");
        var userId = payload.Value<string>("userId") ?? payload.Value<string>("UserId");
        var gameId = payload.Value<string>("gameId") ?? payload.Value<string>("GameId");
        var status = payload.Value<string>("status") ?? payload.Value<string>("Status") ?? "Unknown";

        log.LogInformation(
            "PaymentProcessedEvent: OrderId={OrderId}, UserId={UserId}, GameId={GameId}, Status={Status}",
            orderId, userId, gameId, status);

        if (string.Equals(status, "Approved", StringComparison.OrdinalIgnoreCase))
        {
            SendNotification(
                userId,
                subject: "Pagamento aprovado!",
                body: $"Seu pagamento do pedido {orderId} foi aprovado. O jogo {gameId} ja esta na sua biblioteca.",
                log);
        }
        else
        {
            SendNotification(
                userId,
                subject: "Pagamento nao aprovado",
                body: $"Nao foi possivel processar o pagamento do pedido {orderId}. Status: {status}.",
                log);
        }
    }

    /// <summary>
    /// Simula o envio (email/push/SMS). Trocar por SendGrid, Firebase
    /// Admin SDK etc. em um cenario real - o ponto do exercicio e o
    /// acionamento serverless via fila, nao o provedor de envio.
    /// </summary>
    private static void SendNotification(string? userId, string subject, string body, ILogger log)
    {
        log.LogInformation(
            "[NOTIFICACAO ENVIADA] Para usuario {UserId} | Assunto: {Subject} | Corpo: {Body}",
            userId, subject, body);
    }
}
