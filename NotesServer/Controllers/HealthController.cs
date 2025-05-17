using Microsoft.AspNetCore.Mvc;

namespace NotesServer.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class HealthController : ControllerBase
    {
        [HttpGet]
        [Route("ping")]
        public IActionResult Ping()
        {
            return Ok(new { status = "Ok", message = "Server is running" });
        }
    }
} 