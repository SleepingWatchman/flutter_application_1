using System;
using SQLite;
using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace NotesServer.Models
{
    public class PinboardNote : DatabaseEntity
    {
        [PrimaryKey, AutoIncrement]
        [JsonPropertyName("id")]
        public int Id { get; set; }

        [Required]
        [JsonPropertyName("title")]
        public string Title { get; set; } = string.Empty;

        [Required]
        [JsonPropertyName("content")]
        public string Content { get; set; } = string.Empty;

        [JsonPropertyName("positionX")]
        public double PositionX { get; set; }

        [JsonPropertyName("positionY")]
        public double PositionY { get; set; }

        [JsonPropertyName("width")]
        public double Width { get; set; } = 200.0;

        [JsonPropertyName("height")]
        public double Height { get; set; } = 150.0;

        [JsonPropertyName("backgroundColor")]
        public int BackgroundColor { get; set; } = unchecked((int)0xFF424242);

        [JsonPropertyName("icon")]
        public string Icon { get; set; } = "person";
    }
} 