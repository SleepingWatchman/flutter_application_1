using System.Text.Json.Serialization;

namespace AuthServer.Models;

public class User
{
    public int Id { get; set; }
    
    public string Email { get; set; } = null!;
    
    public string? DisplayName { get; set; }
    
    [JsonPropertyName("photoURL")]
    public string? PhotoUrl { get; set; }
    
    public string PasswordHash { get; set; } = null!;
    
    public DateTime? CreatedAt { get; set; }
    
    public DateTime? UpdatedAt { get; set; }
} 