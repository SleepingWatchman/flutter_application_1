using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace AuthServer.Models;

public class RegisterRequest
{
    [Required]
    [EmailAddress]
    public string Email { get; set; } = string.Empty;
    
    [Required]
    [MinLength(6)]
    public string Password { get; set; } = string.Empty;
    
    [Required]
    public string DisplayName { get; set; } = string.Empty;
}

public class LoginRequest
{
    [Required]
    [EmailAddress]
    public string Email { get; set; } = string.Empty;
    
    [Required]
    public string Password { get; set; } = string.Empty;
}

public class UpdateProfileRequest
{
    public string? DisplayName { get; set; }
    [JsonPropertyName("photoURL")]
    public string? PhotoUrl { get; set; }
}

public class AuthResponse
{
    public string Token { get; set; } = string.Empty;
    public UserDto User { get; set; } = new UserDto();
}

public class UserDto
{
    public int Id { get; set; }
    public string Email { get; set; } = string.Empty;
    public string? DisplayName { get; set; }
    [JsonPropertyName("photoURL")]
    public string? PhotoUrl { get; set; }
    
    public static UserDto FromUser(User user)
    {
        return new UserDto
        {
            Id = user.Id,
            Email = user.Email,
            DisplayName = user.DisplayName,
            PhotoUrl = user.PhotoUrl
        };
    }
} 