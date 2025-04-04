using AuthServer.Models;

namespace AuthServer.Services;

public interface IAuthService
{
    Task<(User user, string token)> RegisterAsync(string email, string password, string displayName);
    Task<(User user, string token)> LoginAsync(string email, string password);
    Task<User> UpdateProfileAsync(int userId, string? displayName, string? photoUrl);
} 