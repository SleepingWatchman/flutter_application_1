using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using AuthServer.Data;
using AuthServer.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

namespace AuthServer.Services;

public class AuthService : IAuthService
{
    private readonly AppDbContext _context;
    private readonly IConfiguration _configuration;

    public AuthService(AppDbContext context, IConfiguration configuration)
    {
        _context = context;
        _configuration = configuration;
    }

    public async Task<(User user, string token)> RegisterAsync(string email, string password, string displayName)
    {
        if (await _context.Users.AnyAsync(u => u.Email == email))
        {
            throw new Exception("User with this email already exists");
        }

        var user = new User
        {
            Email = email,
            DisplayName = displayName,
            PasswordHash = HashPassword(password)
        };

        _context.Users.Add(user);
        await _context.SaveChangesAsync();

        var token = GenerateJwtToken(user);
        return (user, token);
    }

    public async Task<(User user, string token)> LoginAsync(string email, string password)
    {
        Console.WriteLine($"Attempting to login user with email: {email}");
        
        var user = await _context.Users
            .FirstOrDefaultAsync(u => u.Email == email);

        Console.WriteLine($"User found: {user != null}");
        
        if (user == null)
        {
            Console.WriteLine("User not found");
            throw new Exception("Invalid email or password");
        }

        var isPasswordValid = VerifyPassword(password, user.PasswordHash);
        Console.WriteLine($"Password verification result: {isPasswordValid}");

        if (!isPasswordValid)
        {
            Console.WriteLine("Invalid password");
            throw new Exception("Invalid email or password");
        }

        var token = GenerateJwtToken(user);
        Console.WriteLine("Token generated successfully");
        
        return (user, token);
    }

    public async Task<User> UpdateProfileAsync(int userId, string? displayName, string? photoUrl)
    {
        var user = await _context.Users.FindAsync(userId);
        if (user == null)
        {
            throw new Exception("User not found");
        }

        if (displayName != null)
        {
            user.DisplayName = displayName;
        }

        if (photoUrl != null)
        {
            user.PhotoUrl = photoUrl;
        }

        user.UpdatedAt = DateTime.UtcNow;
        await _context.SaveChangesAsync();

        return user;
    }

    private string HashPassword(string password)
    {
        using var sha256 = SHA256.Create();
        var hashedBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(password));
        return Convert.ToBase64String(hashedBytes);
    }

    private bool VerifyPassword(string password, string hash)
    {
        return HashPassword(password) == hash;
    }

    private string GenerateJwtToken(User user)
    {
        var tokenHandler = new JwtSecurityTokenHandler();
        var key = Encoding.ASCII.GetBytes(_configuration["Jwt:Key"] ?? throw new Exception("JWT key not configured"));
        var tokenDescriptor = new SecurityTokenDescriptor
        {
            Subject = new ClaimsIdentity(new[]
            {
                new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
                new Claim(ClaimTypes.Email, user.Email)
            }),
            Expires = DateTime.UtcNow.AddDays(7),
            SigningCredentials = new SigningCredentials(
                new SymmetricSecurityKey(key),
                SecurityAlgorithms.HmacSha256Signature),
            Issuer = _configuration["Jwt:Issuer"],
            Audience = _configuration["Jwt:Audience"]
        };

        var token = tokenHandler.CreateToken(tokenDescriptor);
        return tokenHandler.WriteToken(token);
    }
} 