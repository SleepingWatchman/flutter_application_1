using System.Security.Claims;
using AuthServer.Data;
using AuthServer.Models;
using Microsoft.EntityFrameworkCore;

namespace AuthServer.Services;

public interface IUserService
{
    string GetUserId(ClaimsPrincipal user);
    Task<User?> GetUserByIdAsync(int userId);
    Task<List<User>> GetUsersByIdsAsync(IEnumerable<int> userIds);
    Task<bool> IsUserExistsAsync(int userId);
}

public class UserService : IUserService
{
    private readonly AppDbContext _context;
    private readonly ILogger<UserService> _logger;

    public UserService(AppDbContext context, ILogger<UserService> logger)
    {
        _context = context;
        _logger = logger;
    }

    public string GetUserId(ClaimsPrincipal user)
    {
        var userId = user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        if (string.IsNullOrEmpty(userId))
        {
            throw new UnauthorizedAccessException("User is not authenticated");
        }
        return userId;
    }

    public async Task<User?> GetUserByIdAsync(int userId)
    {
        return await _context.Users.FindAsync(userId);
    }

    public async Task<List<User>> GetUsersByIdsAsync(IEnumerable<int> userIds)
    {
        if (userIds == null)
        {
            throw new ArgumentNullException(nameof(userIds));
        }

        return await _context.Users.Where(u => userIds.Contains(u.Id)).ToListAsync();
    }

    public async Task<bool> IsUserExistsAsync(int userId)
    {
        return await _context.Users.AnyAsync(u => u.Id == userId);
    }
} 