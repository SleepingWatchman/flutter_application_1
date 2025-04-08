using SQLite;
using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace NotesServer.Models
{
    public class Connection : DatabaseEntity
    {
        [PrimaryKey, AutoIncrement]
        [JsonPropertyName("id")]
        public int Id { get; set; }

        [JsonPropertyName("fromId")]
        public int FromId { get; set; }

        [JsonPropertyName("toId")]
        public int ToId { get; set; }

        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("connectionColor")]
        public string ConnectionColor { get; set; } = string.Empty;

        [Required]
        public string Type { get; set; } = string.Empty;
        [Required]
        public string ConnectionString { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
    }
} 