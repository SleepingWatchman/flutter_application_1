using System.Text;
using NotesServer.Models;

namespace NotesServer.Services;

public interface IImageService
{
    Task SaveImageAsync(string userId, ImageData imageData);
    Task<byte[]> GetImageAsync(string userId, string fileName);
}

public class ImageService : IImageService
{
    private readonly string _uploadsDirectory;
    private readonly ILogger<ImageService> _logger;

    public ImageService(ILogger<ImageService> logger)
    {
        _logger = logger;
        _uploadsDirectory = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "uploads");
        Directory.CreateDirectory(_uploadsDirectory);
        _logger.LogInformation("Uploads directory created at: {UploadsDirectory}", _uploadsDirectory);
    }

    public async Task SaveImageAsync(string userId, ImageData imageData)
    {
        try
        {
            var userDirectory = Path.Combine(_uploadsDirectory, userId);
            Directory.CreateDirectory(userDirectory);

            var filePath = Path.Combine(userDirectory, imageData.FileName);
            var imageBytes = Convert.FromBase64String(imageData.Base64Data);
            
            await File.WriteAllBytesAsync(filePath, imageBytes);
            _logger.LogInformation("Image saved successfully: {FilePath}", filePath);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error saving image");
            throw;
        }
    }

    public async Task<byte[]> GetImageAsync(string userId, string fileName)
    {
        try
        {
            var filePath = Path.Combine(_uploadsDirectory, userId, fileName);
            if (!File.Exists(filePath))
            {
                throw new FileNotFoundException($"Image not found: {fileName}");
            }

            return await File.ReadAllBytesAsync(filePath);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting image");
            throw;
        }
    }
} 