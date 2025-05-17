using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NotesServer.Data;
using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using System.IO;

namespace NotesServer.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class ServiceController : ControllerBase
    {
        private readonly ApplicationDbContext _context;
        private readonly ILogger<ServiceController> _logger;

        public ServiceController(ApplicationDbContext context, ILogger<ServiceController> logger)
        {
            _context = context;
            _logger = logger;
        }

        [HttpGet("status")]
        public IActionResult GetStatus()
        {
            try
            {
                return Ok(new 
                { 
                    status = "ok", 
                    timestamp = DateTime.UtcNow,
                    serverTime = DateTime.Now,
                    version = "1.0.0"
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Ошибка при получении статуса сервера");
                return StatusCode(500, new { status = "error", message = ex.Message });
            }
        }

        [HttpGet("databases/count")]
        public async Task<IActionResult> GetDatabasesCount()
        {
            try
            {
                var count = await _context.CollaborativeDatabases.CountAsync();
                return Ok(new { count });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Ошибка при получении количества баз данных");
                return StatusCode(500, new { status = "error", message = ex.Message });
            }
        }

        [HttpGet("disk/space")]
        public IActionResult GetDiskSpace()
        {
            try
            {
                var databasesPath = Path.Combine(Directory.GetCurrentDirectory(), "Databases");
                if (!Directory.Exists(databasesPath))
                {
                    Directory.CreateDirectory(databasesPath);
                }

                var directoryInfo = new DirectoryInfo(databasesPath);
                var totalSize = directoryInfo.GetFiles("*", SearchOption.AllDirectories).Sum(file => file.Length);
                
                return Ok(new 
                { 
                    totalSizeBytes = totalSize,
                    totalSizeMB = Math.Round(totalSize / (1024.0 * 1024.0), 2),
                    filesCount = directoryInfo.GetFiles("*", SearchOption.AllDirectories).Length,
                    path = databasesPath
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Ошибка при получении информации о дисковом пространстве");
                return StatusCode(500, new { status = "error", message = ex.Message });
            }
        }
    }
} 