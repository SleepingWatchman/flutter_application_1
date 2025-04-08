using SQLite;
using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace NotesServer.Models
{
    public class ScheduleEntry : DatabaseEntity
    {
        [PrimaryKey, AutoIncrement]
        [JsonPropertyName("id")]
        public int Id { get; set; }
        [Required]
        [JsonPropertyName("time")]
        public string Time { get; set; } = string.Empty;
        [Required]
        [JsonPropertyName("date")]
        public string Date { get; set; } = string.Empty;
        [Required]
        [JsonPropertyName("note")]
        public string Note { get; set; } = string.Empty;
        [JsonPropertyName("dynamicFieldsJson")]
        public string? DynamicFieldsJson { get; set; }
        [JsonPropertyName("startTime")]
        public DateTime StartTime { get; set; }
        [JsonPropertyName("endTime")]
        public DateTime EndTime { get; set; }
        [JsonPropertyName("isAllDay")]
        public bool IsAllDay { get; set; }
        [JsonPropertyName("createdAt")]
        public DateTime CreatedAt { get; set; }
    }
} 