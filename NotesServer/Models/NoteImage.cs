using SQLite;
using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace NotesServer.Models
{
    public class NoteImage : DatabaseEntity
    {
        [PrimaryKey, AutoIncrement]
        public int Id { get; set; }

        [JsonPropertyName("note_id")]
        public int NoteId { get; set; }

        [JsonPropertyName("file_name")]
        public string FileName { get; set; } = string.Empty;

        [JsonPropertyName("image_data")]
        public string Base64Data { get; set; } = string.Empty;

        public DateTime CreatedAt { get; set; }
    }
} 