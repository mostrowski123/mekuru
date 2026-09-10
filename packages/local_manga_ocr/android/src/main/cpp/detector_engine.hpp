#pragma once
#include <opencv2/core.hpp>
#include <opencv2/dnn.hpp>
#include <stdexcept>
#include <string>
#include <vector>

// Own the detector network with C++ RAII. OpenCV 4.12's Java Net wrapper
// only releases from finalize(), which is unsuitable for pause/cancel cleanup.
class ComicDetector final {
 public:
  ComicDetector(const std::string& model, int threads) {
    cv::setNumThreads(std::max(1, std::min(2, threads)));
    network_ = cv::dnn::readNetFromONNX(model);
    network_.setPreferableBackend(cv::dnn::DNN_BACKEND_OPENCV);
    network_.setPreferableTarget(cv::dnn::DNN_TARGET_CPU);
  }
  std::vector<cv::Mat> run(const cv::Mat& input) {
    network_.setInput(input);
    std::vector<cv::Mat> result;
    network_.forward(result, std::vector<cv::String>{"blk", "seg", "det"});
    if (result.size() != 3 || result[0].total() % 7 != 0 ||
        result[1].total() != 1024 * 1024 || result[2].total() != 2 * 1024 * 1024) {
      throw std::runtime_error("detector_output_shape");
    }
    for (auto& value : result) {
      if (value.type() != CV_32F) throw std::runtime_error("detector_output_type");
      if (!value.isContinuous()) value = value.clone();
    }
    return result;
  }
 private:
  cv::dnn::Net network_;
};
